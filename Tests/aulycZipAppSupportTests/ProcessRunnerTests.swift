import Foundation
import Testing
@testable import aulycZipAppSupport

@Suite("Bounded process runner")
struct ProcessRunnerTests {
    @Test("stdout and stderr are drained while the child is running")
    func drainsBothPipes() throws {
        let result = try ProcessRunner.run(
            "/bin/sh",
            arguments: [
                "-c",
                "i=0; while [ $i -lt 4000 ]; do printf 'stdout-line-%04d\\n' $i; printf 'stderr-line-%04d\\n' $i >&2; i=$((i+1)); done",
            ],
            timeout: 5,
            outputLimit: 256 * 1024
        )

        #expect(result.terminationStatus == 0)
        #expect(result.output.contains("stdout-line-0000"))
        #expect(result.output.contains("stderr-line-0000"))
        #expect(!result.outputWasTruncated)
    }

    @Test("a hung child is terminated at the deadline")
    func timeout() {
        #expect(throws: ProcessRunner.RunError.timedOut) {
            _ = try ProcessRunner.run(
                "/bin/sh",
                arguments: ["-c", "sleep 5"],
                timeout: 0.05,
                outputLimit: 1_024
            )
        }
    }
}
