// LoopFollow
// DexcomSettingsViewModel.swift

import Combine
import Foundation

class DexcomSettingsViewModel: ObservableObject {
    @Published var userName: String = Storage.shared.shareUserName.value {
        willSet {
            if newValue != userName {
                Storage.shared.shareUserName.value = newValue
                PhoneSessionManager.shared.sendConfig()
            }
        }
    }

    @Published var password: String = Storage.shared.sharePassword.value {
        willSet {
            if newValue != password {
                Storage.shared.sharePassword.value = newValue
                PhoneSessionManager.shared.sendConfig()
            }
        }
    }

    @Published var server: String = Storage.shared.shareServer.value {
        willSet {
            if newValue != server {
                Storage.shared.shareServer.value = newValue
                PhoneSessionManager.shared.sendConfig()
            }
        }
    }

    init() {}
}
