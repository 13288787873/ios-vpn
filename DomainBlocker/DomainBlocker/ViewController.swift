import UIKit
import NetworkExtension

class ViewController: UIViewController {
    
    private let domainTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "输入要屏蔽的域名或IP"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let blockButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("启用屏蔽", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var blockedDomains: [String] = []
    private let vpnManager = NEVPNManager.shared()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupVPNManager()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        
        view.addSubview(domainTextField)
        view.addSubview(blockButton)
        
        NSLayoutConstraint.activate([
            domainTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            domainTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            domainTextField.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            domainTextField.heightAnchor.constraint(equalToConstant: 44),
            
            blockButton.topAnchor.constraint(equalTo: domainTextField.bottomAnchor, constant: 20),
            blockButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            blockButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            blockButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        blockButton.addTarget(self, action: #selector(blockButtonTapped), for: .touchUpInside)
    }
    
    private func setupVPNManager() {
        // 请求 VPN 权限
        let vpnManager = NEVPNManager.shared()
        
        vpnManager.loadFromPreferences { [weak self] error in
            if let error = error {
                self?.showAlert(message: "加载VPN配置失败: \(error.localizedDescription)")
                return
            }
            
            // 检查连接状态
            let status = self?.vpnManager.connection.status
            if status == .invalid {
                self?.requestVPNPermissions()
            }
        }
    }
    
    private func requestVPNPermissions() {
        let vpnManager = NEVPNManager.shared()
        
        // 创建一个基本的 VPN 配置来触发权限请求
        let vpnProtocol = NEVPNProtocolIKEv2()
        vpnProtocol.username = "vpn"
        vpnProtocol.serverAddress = "127.0.0.1"
        
        vpnManager.protocolConfiguration = vpnProtocol
        vpnManager.isEnabled = true
        
        vpnManager.saveToPreferences { [weak self] error in
            if let error = error {
                self?.showAlert(message: "请求VPN权限失败: \(error.localizedDescription)")
                return
            }
            
            // 尝试启动 VPN 以触发权限请求
            do {
                try vpnManager.connection.startVPNTunnel()
            } catch {
                self?.showAlert(message: "启动VPN失败: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func blockButtonTapped() {
        guard let domain = domainTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !domain.isEmpty else {
            showAlert(message: "请输入有效的域名或IP")
            return
        }
        
        if !blockedDomains.contains(domain) {
            blockedDomains.append(domain)
            updateVPNConfiguration()
        }
    }
    
    private func updateVPNConfiguration() {
        let vpnManager = NEVPNManager.shared()
        
        // 创建 VPN 协议配置
        let vpnProtocol = NEVPNProtocolIKEv2()
        vpnProtocol.username = "vpn"  // 使用一个默认用户名
        vpnProtocol.passwordReference = nil  // 不使用密码
        vpnProtocol.serverAddress = "127.0.0.1"  // 使用本地地址
        vpnProtocol.remoteIdentifier = "DomainBlocker"
        vpnProtocol.localIdentifier = "client"
        vpnProtocol.useExtendedAuthentication = true
        vpnProtocol.disconnectOnSleep = false
        
        // 配置 IKEv2 安全参数
        vpnProtocol.ikeSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256GCM
        vpnProtocol.ikeSecurityAssociationParameters.integrityAlgorithm = .SHA384
        vpnProtocol.ikeSecurityAssociationParameters.diffieHellmanGroup = .group20
        vpnProtocol.ikeSecurityAssociationParameters.lifetimeMinutes = 1440
        
        vpnProtocol.childSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256GCM
        vpnProtocol.childSecurityAssociationParameters.integrityAlgorithm = .SHA384
        vpnProtocol.childSecurityAssociationParameters.diffieHellmanGroup = .group20
        vpnProtocol.childSecurityAssociationParameters.lifetimeMinutes = 1440
        
        // 配置 DNS 设置
        let dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1"])  // 使用 Cloudflare DNS
        dnsSettings.matchDomains = blockedDomains
        
        // 配置按需规则
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        
        // 应用配置
        vpnManager.protocolConfiguration = vpnProtocol
        vpnManager.onDemandRules = [rule]
        vpnManager.isOnDemandEnabled = true
        vpnManager.isEnabled = true
        
        // 设置本地 DNS 代理
        if let tunnelProtocol = vpnManager.protocolConfiguration as? NETunnelProviderProtocol {
            tunnelProtocol.providerConfiguration = [
                "dns": ["1.1.1.1", "1.0.0.1"],
                "blockedDomains": blockedDomains
            ]
        }
        
        // 保存配置
        vpnManager.loadFromPreferences { [weak self] error in
            if let error = error {
                self?.showAlert(message: "加载VPN配置失败: \(error.localizedDescription)")
                return
            }
            
            vpnManager.saveToPreferences { [weak self] error in
                if let error = error {
                    self?.showAlert(message: "保存VPN配置失败: \(error.localizedDescription)")
                    return
                }
                
                // 启动 VPN
                do {
                    try vpnManager.connection.startVPNTunnel()
                    self?.showAlert(message: "域名屏蔽规则已更新并启动")
                } catch {
                    self?.showAlert(message: "启动VPN失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
} 