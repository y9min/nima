import Foundation
import SwiftUI
import Observation

@Observable
final class AuthStore {
    @AppStorage("isLoggedIn") var isLoggedIn: Bool = false
    @AppStorage("userEmail") var userEmail: String = ""
    
    func login(email: String) {
        isLoggedIn = true
        userEmail = email
    }
    
    func logout() {
        isLoggedIn = false
        userEmail = ""
    }
}
