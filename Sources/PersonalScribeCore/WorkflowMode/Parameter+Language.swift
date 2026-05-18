import Foundation

public extension Parameter where Value == String? {
    var resolved: String? {
        ParameterResolver.resolve(self, from: .standard)
    }
}
