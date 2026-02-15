import Foundation
import Observation

@Observable
class MagicSignInService {
    var email: String = ""
    var code: String = ""
    var isCodeSent: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    
    // In a real app, this would make an API call to send the code
    func sendMagicCode(email: String) async throws {
        isLoading = true
        errorMessage = nil
        
        // Simulate API call delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Validate email format
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            throw MagicSignInError.invalidEmail
        }
        
        // In production, this would call your backend API
        // For now, we'll simulate success
        self.email = email
        self.isCodeSent = true
        self.isLoading = false
        
        // Generate a mock code (in production, this comes from your backend)
        // For demo purposes, we'll use a simple 6-digit code
        // In real implementation, the backend sends this via email
    }
    
    // In a real app, this would verify the code with your backend
    func verifyCode(_ code: String) async throws -> Bool {
        isLoading = true
        errorMessage = nil
        
        // Simulate API call delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // In production, this would verify with your backend
        // For demo, accept any 6-digit code
        let cleanedCode = code.replacingOccurrences(of: " ", with: "")
        guard cleanedCode.count == 6, cleanedCode.allSatisfy({ $0.isNumber }) else {
            errorMessage = "Please enter a valid 6-digit code"
            isLoading = false
            throw MagicSignInError.invalidCode
        }
        
        self.code = cleanedCode
        self.isLoading = false
        
        // In production, return the result from your backend
        return true
    }
    
    func reset() {
        email = ""
        code = ""
        isCodeSent = false
        isLoading = false
        errorMessage = nil
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

enum MagicSignInError: LocalizedError {
    case invalidEmail
    case invalidCode
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address"
        case .invalidCode:
            return "Please enter a valid 6-digit code"
        case .networkError:
            return "Network error. Please try again."
        }
    }
}
