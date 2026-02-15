import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

enum WebhookSignature {
    static func sign(secret: String, timestamp: String, body: Data) -> String {
        var payload = Data(timestamp.utf8)
        payload.append(Data([0x2E])) // "."
        payload.append(body)

        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(secret: String, timestamp: String, body: Data, signature: String) -> Bool {
        let expected = sign(secret: secret, timestamp: timestamp, body: body)
        return secureCompare(lhs: expected, rhs: signature)
    }

    private static func secureCompare(lhs: String, rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else {
            return false
        }
        var mismatch: UInt8 = 0
        for index in left.indices {
            mismatch |= left[index] ^ right[index]
        }
        return mismatch == 0
    }
}
