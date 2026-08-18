@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// The S1 date range: what it defaults to, how far it may stretch, and what
/// happens at the edges. All of it lives on `ImportFlowModel` rather than in the
/// sheet, so it can be exercised without a view.
@MainActor
final class ImportDateRangeTests: XCTestCase {
    private let calendar = Calendar.current

    /// 2026-08-18, a Tuesday — fixed so "today" cannot drift under the tests.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 14)) ?? .now
    }

    private func makeModel() throws -> ImportFlowModel {
        ImportFlowModel(
            config: AppConfig.loadOrDie(),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            source: StubPhotoSource(),
            now: today
        )
    }

    private struct StubPhotoSource: ImportPhotoProviding {
        func photos(matching query: ImportQuery) async -> [ImportPhoto] { [] }
        func albums() async -> [PhotoAlbum] { [] }
    }

    private func day(_ offset: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }

    private func dayCount(_ model: ImportFlowModel) -> Int {
        let from = calendar.startOfDay(for: model.startDate)
        let to = calendar.startOfDay(for: model.endDate)
        return (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
    }

    // MARK: - The default

    /// **A config key is a contract.** `default_range_days: 7` promised a
    /// seven-day range and delivered eight: the seed was `now − 7`, and
    /// `dayBounds` widens to whole calendar days at both ends. The behaviour was
    /// moved to the name rather than the name to the behaviour.
    func testTheDefaultRangeCoversExactlyTheConfiguredNumberOfDays() throws {
        let config = AppConfig.loadOrDie()
        let model = try makeModel()
        XCTAssertEqual(
            dayCount(model), config.photoImport.defaultRangeDays,
            "the default range must cover default_range_days calendar days, both ends counted"
        )
    }

    // MARK: - The month-reset that used to fire

    /// **The bug, stated as the case that produced it.** `linkEndToStart` reset
    /// the end whenever the new start sat in a *different month*, so setting an
    /// end and then reaching back to a previous month silently collapsed the
    /// range to a single day. Nothing about a month boundary means anything here.
    func testPickingAStartInAnEarlierMonthKeepsTheEnd() throws {
        let model = try makeModel()
        // End on 5 August, start on 30 July — a five-day trip across the boundary.
        model.endDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5)))
        model.endDateChanged()
        let intendedEnd = model.endDate

        model.startDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 30)))
        model.startDateChanged()

        XCTAssertEqual(
            calendar.startOfDay(for: model.endDate), calendar.startOfDay(for: intendedEnd),
            "a start in an earlier month must not move the end"
        )
        XCTAssertEqual(dayCount(model), 7, "30 July to 5 August is seven days")
    }

    /// The half of the old rule that was always right: an end *before* the start
    /// is not a range, so it follows the start.
    func testAnEndBeforeTheStartFollowsIt() throws {
        let model = try makeModel()
        model.startDate = day(-3, from: today)
        model.startDateChanged()
        model.endDate = day(-10, from: today)
        model.endDateChanged()

        XCTAssertEqual(dayCount(model), 1, "an inverted range collapses to the day picked")
        XCTAssertLessThanOrEqual(model.startDate, model.endDate)
    }

    // MARK: - The sliding window

    /// Inside the window nothing moves; at the limit nothing moves; past it the
    /// **other** end follows. The input is never rejected — a refusal leaves
    /// someone unable to see what they did wrong.
    func testTheWindowSlidesRatherThanRejectingWhenTheStartMovesBack() throws {
        let maxDays = AppConfig.loadOrDie().photoImport.maxRangeDays
        for span in [20, 21, 22] {
            let model = try makeModel()
            model.endDate = today
            model.endDateChanged()
            model.startDate = day(-(span - 1), from: today)
            model.startDateChanged()

            XCTAssertEqual(
                dayCount(model), min(span, maxDays),
                "a \(span)-day pick from the start must settle at \(min(span, maxDays)) days"
            )
            XCTAssertEqual(
                calendar.startOfDay(for: model.startDate),
                calendar.startOfDay(for: day(-(span - 1), from: today)),
                "the start is what the user just picked and must not move"
            )
        }
    }

    func testTheWindowSlidesRatherThanRejectingWhenTheEndMovesForward() throws {
        let maxDays = AppConfig.loadOrDie().photoImport.maxRangeDays
        for span in [20, 21, 22] {
            let model = try makeModel()
            let anchorStart = day(-40, from: today)
            model.startDate = anchorStart
            model.startDateChanged()
            let pickedEnd = day(span - 1, from: anchorStart)
            model.endDate = pickedEnd
            model.endDateChanged()

            XCTAssertEqual(
                dayCount(model), min(span, maxDays),
                "a \(span)-day pick from the end must settle at \(min(span, maxDays)) days"
            )
            XCTAssertEqual(
                calendar.startOfDay(for: model.endDate), calendar.startOfDay(for: pickedEnd),
                "the end is what the user just picked and must not move"
            )
        }
    }

    // MARK: - The future

    /// A range ending tomorrow holds no photograph, and with the sliding window
    /// it would drag the start into the future too.
    func testNeitherEndMayReachIntoTheFuture() throws {
        let model = try makeModel()
        model.endDate = day(30, from: today)
        model.endDateChanged()
        XCTAssertLessThanOrEqual(model.endDate, model.latestSelectableDate, "the end must clamp to today")

        model.startDate = day(30, from: today)
        model.startDateChanged()
        XCTAssertLessThanOrEqual(model.startDate, model.latestSelectableDate, "the start must clamp to today")
        XCTAssertLessThanOrEqual(model.endDate, model.latestSelectableDate)
    }
}
