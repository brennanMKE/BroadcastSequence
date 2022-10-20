import XCTest
import AsyncTesting
@testable import BroadcastSequence

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        let nanoseconds = UInt64(seconds * Double(NSEC_PER_SEC))
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

extension Sequence where Element == Int {
    /// Convert to asynchronous sequence.
    var async: AsyncStream<Self.Element> {
        let stream = AsyncStream(Element.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                await Task.yield()
                for element in self {
                    continuation.yield(element)
                }
                continuation.finish()
            }
        }
        return stream
    }

}

final class BroadcastSequenceTests: XCTestCase {

    func testNumberStream() async throws {
        let stream = [1, 2, 3, 4, 5].async
        for await number in stream {
            print(number)
        }
    }

    func testSingleConsumer() async throws {
        let stream = [1, 2, 3, 4, 5].async
        let source = BroadcastSource(source: stream)
        let consumer = await source.consume(name: "A")
        for await number in consumer {
            print("\(number) [\(await consumer.name ?? "-")]")
        }
    }

    func testMultipleConsumers() async throws {
        let input = [1, 2, 3, 4, 5]
        let stream = input.async
        let source = BroadcastSource(source: stream)
        let consumerA = await source.consume(name: "A")
        let consumerB = await source.consume(name: "B")
        let consumerC = await source.consume(name: "C")
        let consumers = [consumerA, consumerB, consumerC]

        let done = asyncExpectation(description: "done", expectedFulfillmentCount: consumers.count)

        for consumer in consumers {
            Task {
                for await number in consumer {
                    print("\(number) [\(await consumer.name ?? "-")]")
                }
                await done.fulfill()
            }
        }

        await waitForExpectations([done])
    }

}
