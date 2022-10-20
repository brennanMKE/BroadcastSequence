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
        let input = [1, 2, 3, 4, 5]
        let stream = input.async
        let output = await Task {
            var result: [Int] = []
            for await number in stream {
                result.append(number)
            }
            return result
        }.value
        XCTAssertEqual(input, output)
    }

    func testSingleConsumer() async throws {
        let input = [1, 2, 3, 4, 5]
        let stream = input.async
        let source = BroadcastSource(source: stream)
        let consumer = await source.consume(name: "A")
        await source.resume()

        let done = asyncExpectation(description: "done")

        let task = Task {
            var result: [Int] = []
            for await number in consumer {
                result.append(number)
            }
            await done.fulfill()
            return result
        }
        let output = await task.value

        await waitForExpectations([done])

        XCTAssertEqual(input, output)
    }

    func testSingleConsumerWithDiscard() async throws {
        let input = [1, 2, 3, 4, 5]
        let stream = input.async
        let source = BroadcastSource(source: stream)
        let consumer = await source.consume(name: "A")
        await source.resume()

        let done = asyncExpectation(description: "done")

        let task = Task {
            var result: [Int] = []
            for await number in consumer {
                if number == 3 {
                    await source.discard(consumer: consumer)
                    break
                }
                result.append(number)
            }
            await done.fulfill()
            return result
        }
        let output = await task.value

        await waitForExpectations([done])

        XCTAssertGreaterThan(input.count, output.count)
        XCTAssertEqual(Array(input[0..<output.count]), output, "Consumer \(name)")
    }

    func testMultipleConsumers() async throws {
        let input = [1, 2, 3, 4, 5]
        let stream = input.async
        let source = BroadcastSource(source: stream)
        let consumerA = await source.consume(name: "A")
        let consumerB = await source.consume(name: "B")
        let consumerC = await source.consume(name: "C")
        let consumers = [consumerA, consumerB, consumerC]
        await source.resume()

        let done = asyncExpectation(description: "done", expectedFulfillmentCount: consumers.count)

        for consumer in consumers {
            Task {
                let name = await consumer.name ?? "-"
                var output: [Int] = []
                for await number in consumer {
                    output.append(number)
                }
                XCTAssertEqual(input, output, "Consumer \(name)")
                await done.fulfill()
            }
        }

        await waitForExpectations([done])
    }

    func testMultipleConsumersWithDiscard() async throws {
        let input = [1, 2, 3, 4, 5]
        let stream = input.async
        let source = BroadcastSource(source: stream)
        let consumers = [
            (await source.consume(name: "A"), asyncExpectation(description: "done A")),
            (await source.consume(name: "B"), asyncExpectation(description: "done B")),
            (await source.consume(name: "C"), asyncExpectation(description: "done C")),
        ]
        let discardName = "A"
        await source.resume()

        for (consumer, done) in consumers {
            Task {
                let name = await consumer.name ?? "-"
                let task = Task {
                    var result: [Int] = []
                    for await number in consumer {
                        if number == 3, name == discardName {
                            await source.discard(consumer: consumer)
                            break
                        }
                        result.append(number)
                    }
                    return result
                }

                let output = await task.value

                if name != discardName {
                    XCTAssertEqual(input, output, "Consumer \(name)")
                } else {
                    XCTAssertGreaterThan(input.count, output.count)
                    XCTAssertEqual(Array(input[0..<output.count]), output, "Consumer \(name)")
                }
                await done.fulfill()
            }
        }

        let expectations = consumers.map { $0.1 }
        await waitForExpectations(expectations)
    }

}
