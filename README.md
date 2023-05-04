# NetworkScanner

[![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/wadetregaskis/NetworkScanner.svg)]()
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwadetregaskis%2FNetworkScanner%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/wadetregaskis/NetworkScanner)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwadetregaskis%2FNetworkScanner%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/wadetregaskis/NetworkScanner)
[![GitHub build results](https://github.com/wadetregaskis/NetworkScanner/actions/workflows/swift.yml/badge.svg)](https://github.com/wadetregaskis/NetworkScanner/actions/workflows/swift.yml)

Provides a way to scan a specific network or the local networks for hosts which satisfy an arbitrary condition.

The API and implementation use Swift Structured Concurrency (await/async, Task, etc).

For example, to find all HTTPS servers on the local network that respond successfully to a request for their main page:

```swift
import Foundation
import NetworkScanner

let scanner = NetworkScanner(concurrencyLimit: 250) { address in
    guard let URL = URL(string: "https://\(address)") else {
        throw Errors.unableToConstructURL(address: address)
    }
    
    do {
        _ = try await session.data(from: URL)
        return .hit
    } catch {
        return .miss
    }
}

for try await result in scanner {
    print(result) // e.g. "192.168.0.10: Hit"
}

enum Errors: Error {
    case unableToConstructURL(address: String)
}
```

See [the documentation](https://swiftpackageindex.com/wadetregaskis/NetworkScanner/main/documentation) for more details, as well as the included demo application for more probe examples.
