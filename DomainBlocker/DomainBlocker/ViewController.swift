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
        // 创建一个基本的 VPN 配置
        let vpnProtocol = NEVPNProtocolIKEv2()
        vpnProtocol.username = "vpn"
        vpnProtocol.serverAddress = "127.0.0.1"
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
        
        // 创建 VPN Manager
        let manager = NEVPNManager.shared()
        manager.protocolConfiguration = vpnProtocol
        manager.isEnabled = true
        manager.isOnDemandEnabled = true
        
        // 配置按需规则
        let connectRule = NEOnDemandRuleConnect()
        connectRule.interfaceTypeMatch = .any
        manager.onDemandRules = [connectRule]
        
        // 创建 DNS 代理配置
        let providerProtocol = NETunnelProviderProtocol()
        providerProtocol.providerConfiguration = [
            "dns": ["1.1.1.1", "1.0.0.1"],
            "dnsSettings": [
                "servers": ["1.1.1.1", "1.0.0.1"],
                "matchDomains": []
            ]
        ]
        
        // 先加载现有配置
        manager.loadFromPreferences { [weak self] error in
            if let error = error {
                self?.showAlert(message: "加载VPN配置失败: \(error.localizedDescription)")
                return
            }
            
            // 保存配置以触发权限请求
            manager.saveToPreferences { [weak self] error in
                if let error = error {
                    if (error as NSError).code == NEVPNError.configurationInvalid.rawValue {
                        // 配置无效，可能是权限问题，尝试请求权限
                        self?.showVPNPermissionAlert()
                    } else {
                        self?.showAlert(message: "配置VPN失败: \(error.localizedDescription)")
                    }
                    return
                }
                
                // 配置成功，尝试启动 VPN
                do {
                    try manager.connection.startVPNTunnel()
                } catch {
                    if (error as NSError).code == NEVPNError.configurationInvalid.rawValue {
                        self?.showVPNPermissionAlert()
                    } else {
                        self?.showAlert(message: "启动VPN失败: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func showVPNPermissionAlert() {
        let alert = UIAlertController(
            title: "需要VPN权限",
            message: "此应用需要VPN权限来实现域名屏蔽功能。请在设置中允许VPN配置。",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "打开设置", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func updateVPNConfiguration() {
        let manager = NEVPNManager.shared()
        
        // 创建 VPN 协议配置
        let vpnProtocol = NEVPNProtocolIKEv2()
        vpnProtocol.username = "vpn"
        vpnProtocol.serverAddress = "127.0.0.1"
        vpnProtocol.remoteIdentifier = "DomainBlocker"
        vpnProtocol.localIdentifier = "client"
        vpnProtocol.useExtendedAuthentication = true
        vpnProtocol.disconnectOnSleep = false
        
        // 创建 DNS 代理配置
        let providerProtocol = NETunnelProviderProtocol()
        providerProtocol.providerConfiguration = [
            "dns": ["1.1.1.1", "1.0.0.1"],
            "dnsSettings": [
                "servers": ["1.1.1.1", "1.0.0.1"],
                "matchDomains": blockedDomains
            ]
        ]
        
        // 配置按需规则
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        
        // 应用配置
        manager.protocolConfiguration = vpnProtocol
        manager.onDemandRules = [rule]
        manager.isOnDemandEnabled = true
        manager.isEnabled = true
        
        // 保存配置
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                if (error as NSError).code == NEVPNError.configurationInvalid.rawValue {
                    self?.showVPNPermissionAlert()
                } else {
                    self?.showAlert(message: "保存VPN配置失败: \(error.localizedDescription)")
                }
                return
            }
            
            // 启动 VPN
            do {
                try manager.connection.startVPNTunnel()
                self?.showAlert(message: "域名屏蔽规则已更新并启动")
            } catch {
                if (error as NSError).code == NEVPNError.configurationInvalid.rawValue {
                    self?.showVPNPermissionAlert()
                } else {
                    self?.showAlert(message: "启动VPN失败: \(error.localizedDescription)")
                }
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
    
    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
} 