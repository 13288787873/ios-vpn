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
        vpnManager.loadFromPreferences { [weak self] error in
            if let error = error {
                self?.showAlert(message: "加载VPN配置失败: \(error.localizedDescription)")
                return
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
        let vpnProtocol = NEVPNProtocolIPSec()
        vpnProtocol.remoteIdentifier = "VPN_IDENTIFIER"
        vpnProtocol.serverAddress = "VPN_SERVER"
        
        // 创建DNS规则
        let dnsSettings = NEDNSSettings(servers: ["1.1.1.1"]) // 使用Cloudflare DNS
        dnsSettings.matchDomains = blockedDomains
        
        // 创建网络规则
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        
        // 配置VPN
        let vpnManager = NEVPNManager.shared()
        vpnManager.protocolConfiguration = vpnProtocol
        vpnManager.onDemandRules = [rule]
        vpnManager.isEnabled = true
        
        // 设置DNS
        if let tunnelProtocol = vpnManager.protocolConfiguration as? NETunnelProviderProtocol {
            tunnelProtocol.providerConfiguration = [
                "dns": dnsSettings.servers,
                "blockedDomains": blockedDomains
            ]
        }
        
        vpnManager.saveToPreferences { [weak self] error in
            if let error = error {
                self?.showAlert(message: "保存VPN配置失败: \(error.localizedDescription)")
                return
            }
            
            // 启动VPN
            do {
                try vpnManager.connection.startVPNTunnel()
                self?.showAlert(message: "域名屏蔽规则已更新并启动")
            } catch {
                self?.showAlert(message: "启动VPN失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
} 