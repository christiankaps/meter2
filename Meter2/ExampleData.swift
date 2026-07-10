import Foundation

enum ExampleData {
    static let meterIDs: Set<UUID> = [
        UUID(uuidString: "B09D19F5-1746-4B26-8A02-03010D6A0001")!,
        UUID(uuidString: "B09D19F5-1746-4B26-8A02-03010D6A0002")!,
        UUID(uuidString: "B09D19F5-1746-4B26-8A02-03010D6A0003")!
    ]

    static func isExampleMeter(_ meter: Meter) -> Bool {
        meterIDs.contains(meter.id)
    }

    static func makeMeters(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Meter] {
        let startOfToday = calendar.startOfDay(for: referenceDate)

        return [
            makeMeter(
                id: requiredID(1),
                name: String(localized: "exampleData.electricity.name"),
                kind: .electricity,
                location: String(localized: "exampleData.location.home"),
                unit: "kWh",
                decimalPrecision: 1,
                baseValue: 8_420,
                monthlyUsage: [265, 238, 224, 211, 198, 186, 181, 190, 205, 224, 247, 272],
                referenceDate: startOfToday,
                calendar: calendar,
                tariff: (0.32, 12.50)
            ),
            makeMeter(
                id: requiredID(2),
                name: String(localized: "exampleData.water.name"),
                kind: .water,
                location: String(localized: "exampleData.location.basement"),
                unit: "L",
                decimalPrecision: 0,
                baseValue: 128_400,
                monthlyUsage: [4_100, 3_850, 3_920, 4_020, 4_180, 4_450, 4_720, 4_660, 4_230, 4_050, 3_940, 4_120],
                referenceDate: startOfToday,
                calendar: calendar
            ),
            makeMeter(
                id: requiredID(3),
                name: String(localized: "exampleData.gas.name"),
                kind: .gas,
                location: String(localized: "exampleData.location.utilityRoom"),
                unit: "m³",
                decimalPrecision: 1,
                baseValue: 3_260,
                monthlyUsage: [142, 118, 82, 48, 24, 12, 8, 10, 28, 62, 104, 151],
                referenceDate: startOfToday,
                calendar: calendar,
                tariff: (0.12, 9.80)
            )
        ]
    }

    static func makeMissingMeters(
        existingMeterIDs: Set<UUID>,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Meter] {
        makeMeters(referenceDate: referenceDate, calendar: calendar)
            .filter { !existingMeterIDs.contains($0.id) }
    }

    static func referenceDate(for existingMeters: [Meter], fallback: Date = Date()) -> Date {
        existingMeters
            .filter(isExampleMeter)
            .compactMap(\.latestReading?.recordedAt)
            .max() ?? fallback
    }

    private static func requiredID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "B09D19F5-1746-4B26-8A02-03010D6A%04d", suffix))!
    }

    private static func makeMeter(
        id: UUID,
        name: String,
        kind: MeterKind,
        location: String,
        unit: String,
        decimalPrecision: Int,
        baseValue: Double,
        monthlyUsage: [Double],
        referenceDate: Date,
        calendar: Calendar,
        tariff: (unitPrice: Double, baseFee: Double)? = nil
    ) -> Meter {
        let meter = Meter(
            id: id,
            name: name,
            kind: kind,
            location: location,
            unit: unit,
            decimalPrecision: decimalPrecision,
            createdAt: calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate,
            updatedAt: referenceDate
        )

        var value = baseValue
        let dates = (0...monthlyUsage.count).compactMap {
            calendar.date(byAdding: .month, value: $0 - monthlyUsage.count, to: referenceDate)
        }
        meter.readings = dates.enumerated().map { index, date in
            if index > 0 {
                let month = calendar.component(.month, from: date)
                value += monthlyUsage[month - 1]
            }
            return MeterReading(
                value: value,
                recordedAt: date,
                recordedAtGranularity: .dateOnly,
                meter: meter
            )
        }

        if let tariff {
            meter.tariffs = [
                MeterTariff(
                    currencyCode: "EUR",
                    unitPrice: tariff.unitPrice,
                    baseFee: tariff.baseFee,
                    validFrom: dates.first ?? referenceDate,
                    meter: meter
                )
            ]
        }

        return meter
    }
}
