import Foundation
import EnTransCore

let result = EnTransChecks.run()
if result.failures.isEmpty {
    print("ok \(result.count)")
} else {
    for failure in result.failures {
        print("FAIL \(failure)")
    }
    exit(1)
}
