import CoreLocation
import Foundation

/// 事故データバイナリの読み込みに関するエラー定義。
enum AccidentDataError: LocalizedError {
    case fileNotFound(String)
    case fileReadFailed(Error)
    case invalidHeader
    case unsupportedVersion(UInt32)
    case corruptedPayload(expectedBytes: Int, actualBytes: Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "事故データファイル（\(name)）がバンドル内に見つかりません。"
        case .fileReadFailed(let underlying):
            return "事故データファイルの読み込みに失敗しました: \(underlying.localizedDescription)"
        case .invalidHeader:
            return "事故データファイルのヘッダ形式が不正です。"
        case .unsupportedVersion(let ver):
            return "未対応のデータフォーマットバージョンです（v\(ver)）。"
        case .corruptedPayload(let expected, let actual):
            return "事故データファイルのサイズが不正です（期待値: \(expected)B, 実際: \(actual)B）。"
        }
    }
}

/// 地図の矩形表示領域（緯度・経度の最小/最大範囲）。
struct CoordinateBoundingBox: Equatable, Sendable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLatitude && latitude <= maxLatitude &&
            longitude >= minLongitude && longitude <= maxLongitude
    }
}

/// 警察庁オープンデータのバイナリ（`accidents.bin`）をメモリマップで高速に検索するストア。
final class AccidentDataStore: @unchecked Sendable {
    static let headerSize = 16
    static let recordSize = 32
    static let expectedMagic: [UInt8] = [0x54, 0x41, 0x43, 0x44] // "TACD"

    private let data: Data
    /// 総レコード件数
    let totalCount: Int
    /// 収録データ内の最新年（空ストアの場合は現在年）
    let latestYear: UInt16
    /// 収録データ内に存在する発生年の一覧（降順）
    let availableYears: [UInt16]

    /// バンドル内の `accidents.bin` から初期化する。失敗時はエラーログを記録して空ストアにフォールバック可能。
    convenience init(resourceName: String = "accidents", fileExtension: String = "bin", bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: resourceName, withExtension: fileExtension) else {
            let error = AccidentDataError.fileNotFound("\(resourceName).\(fileExtension)")
            AppLogger.logError(AppLogger.data, context: "リソースURL取得失敗", error: error)
            throw error
        }
        try self.init(contentsOf: url)
    }

    /// 指定ファイルURLからメモリマップ（`.mappedIfSafe`）で初期化する。
    convenience init(contentsOf url: URL) throws {
        let loadedData: Data
        do {
            loadedData = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            let wrapped = AccidentDataError.fileReadFailed(error)
            AppLogger.logError(AppLogger.data, context: "バイナリ読み込み失敗", error: wrapped)
            throw wrapped
        }
        try self.init(data: loadedData)
    }

    /// メモリ上の `Data` から初期化する（単体テストでも直接利用可能）。
    init(data: Data) throws {
        guard data.count >= Self.headerSize else {
            let error = AccidentDataError.invalidHeader
            AppLogger.logError(AppLogger.data, context: "ヘッダサイズ不足", error: error)
            throw error
        }

        let magic = [data[0], data[1], data[2], data[3]]
        guard magic == Self.expectedMagic else {
            let error = AccidentDataError.invalidHeader
            AppLogger.logError(AppLogger.data, context: "マジックバイト不一致", error: error)
            throw error
        }

        let version = Self.readUInt32LE(from: data, offset: 4)
        guard version == 1 else {
            let error = AccidentDataError.unsupportedVersion(version)
            AppLogger.logError(AppLogger.data, context: "未対応バージョン", error: error)
            throw error
        }

        let rawCount = Int(Self.readUInt32LE(from: data, offset: 8))
        guard rawCount >= 0 && rawCount <= 10_000_000 else {
            let error = AccidentDataError.invalidHeader
            AppLogger.logError(AppLogger.data, context: "レコード件数異常 (\(rawCount))", error: error)
            throw error
        }
        let expectedSize = Self.headerSize + rawCount * Self.recordSize
        guard data.count >= expectedSize else {
            let error = AccidentDataError.corruptedPayload(expectedBytes: expectedSize, actualBytes: data.count)
            AppLogger.logError(AppLogger.data, context: "ペイロードサイズ不整合", error: error)
            throw error
        }

        self.data = data
        self.totalCount = rawCount

        var yearSet: Set<UInt16> = []
        var maxYear: UInt16 = 0
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for idx in 0..<rawCount {
                let ptr = base.advanced(by: Self.headerSize + idx * Self.recordSize)
                let year = UInt16(ptr[8]) | (UInt16(ptr[9]) << 8)
                if year > 0 {
                    yearSet.insert(year)
                    if year > maxYear { maxYear = year }
                }
            }
        }
        self.availableYears = yearSet.sorted(by: >)
        self.latestYear = maxYear > 0 ? maxYear : AccidentFilter.defaultReferenceYear
        AppLogger.data.info("事故データストア初期化完了: 総件数 \(rawCount) 件 (最新年: \(self.latestYear))")
    }

    private init(empty: Bool) {
        self.data = Data()
        self.totalCount = 0
        self.latestYear = AccidentFilter.defaultReferenceYear
        self.availableYears = []
    }

    /// 空のフォールバック用ストアを安全に生成する（強制アンラップ不使用）。
    static func emptyStore() -> AccidentDataStore {
        AccidentDataStore(empty: true)
    }

    /// 指定インデックスの事故レコードをデコードして返す。範囲外の場合は `nil` を返す。
    func record(at index: Int) -> AccidentRecord? {
        guard index >= 0 && index < totalCount else { return nil }
        return data.withUnsafeBytes { rawBuffer -> AccidentRecord? in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            let ptr = base.advanced(by: Self.headerSize + index * Self.recordSize)
            return Self.decodeRecord(at: ptr, id: index)
        }
    }

    /// 指定された矩形領域（Bounding Box）およびフィルタ条件に合致する事故レコードを高速検索する。
    /// 死亡事故を優先的に残しつつ、上限件数 `filter.maxVisibleRecords` 内に収める。
    func queryRecords(
        in box: CoordinateBoundingBox,
        filter: AccidentFilter
    ) -> (records: [AccidentRecord], totalMatchedInBox: Int) {
        guard totalCount > 0 else { return ([], 0) }

        let minLatE6 = Int32((box.minLatitude * 1_000_000.0).rounded(.down))
        let maxLatE6 = Int32((box.maxLatitude * 1_000_000.0).rounded(.up))
        let minLonE6 = Int32((box.minLongitude * 1_000_000.0).rounded(.down))
        let maxLonE6 = Int32((box.maxLongitude * 1_000_000.0).rounded(.up))
        let limit = max(50, filter.maxVisibleRecords)

        return data.withUnsafeBytes { rawBuffer -> ([AccidentRecord], Int) in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return ([], 0)
            }

            var matchedIndices: [Int] = []
            matchedIndices.reserveCapacity(min(totalCount, 4096))

            for idx in 0..<totalCount {
                let ptr = base.advanced(by: Self.headerSize + idx * Self.recordSize)
                let latE6 = Self.readInt32LE(ptr: ptr, offset: 0)
                if latE6 < minLatE6 || latE6 > maxLatE6 { continue }
                let lonE6 = Self.readInt32LE(ptr: ptr, offset: 4)
                if lonE6 < minLonE6 || lonE6 > maxLonE6 { continue }

                if !Self.matchesFilterRaw(ptr: ptr, filter: filter, latestYear: latestYear) {
                    continue
                }
                matchedIndices.append(idx)
            }

            let totalMatched = matchedIndices.count
            if totalMatched == 0 {
                return ([], 0)
            }

            var selected: [AccidentRecord] = []
            selected.reserveCapacity(min(totalMatched, limit))

            if totalMatched <= limit {
                for idx in matchedIndices {
                    let ptr = base.advanced(by: Self.headerSize + idx * Self.recordSize)
                    selected.append(Self.decodeRecord(at: ptr, id: idx))
                }
            } else {
                // 死亡事故を最優先で抽出し、残りを均等ストライドでサンプリングする
                var nonFatalIndices: [Int] = []
                nonFatalIndices.reserveCapacity(totalMatched)
                for idx in matchedIndices {
                    let ptr = base.advanced(by: Self.headerSize + idx * Self.recordSize)
                    if ptr[14] == 1 || ptr[15] > 0 {
                        if selected.count < limit {
                            selected.append(Self.decodeRecord(at: ptr, id: idx))
                        }
                    } else {
                        nonFatalIndices.append(idx)
                    }
                }
                let remaining = limit - selected.count
                if remaining > 0 && !nonFatalIndices.isEmpty {
                    let step = max(1, nonFatalIndices.count / remaining)
                    var i = 0
                    while i < nonFatalIndices.count && selected.count < limit {
                        let idx = nonFatalIndices[i]
                        let ptr = base.advanced(by: Self.headerSize + idx * Self.recordSize)
                        selected.append(Self.decodeRecord(at: ptr, id: idx))
                        i += step
                    }
                }
            }

            return (selected, totalMatched)
        }
    }

    /// 指定された中心座標から半径 `radiusMeters` メートル以内の全事故レコードを検索する。
    func recordsNear(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Double,
        filter: AccidentFilter? = nil
    ) -> [AccidentRecord] {
        guard totalCount > 0, radiusMeters > 0 else { return [] }

        // 緯度1度 ≒ 111,320m、経度1度 ≒ 111,320m × cos(lat)
        let latDelta = radiusMeters / 111_320.0
        let cosLat = max(0.2, cos(coordinate.latitude * .pi / 180.0))
        let lonDelta = radiusMeters / (111_320.0 * cosLat)

        let box = CoordinateBoundingBox(
            minLatitude: coordinate.latitude - latDelta,
            maxLatitude: coordinate.latitude + latDelta,
            minLongitude: coordinate.longitude - lonDelta,
            maxLongitude: coordinate.longitude + lonDelta
        )

        var broadFilter = filter ?? AccidentFilter()
        broadFilter.maxVisibleRecords = 10_000

        let (candidates, _) = queryRecords(in: box, filter: broadFilter)
        let centerLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return candidates.filter { rec in
            let loc = CLLocation(latitude: rec.latitude, longitude: rec.longitude)
            return loc.distance(from: centerLocation) <= radiusMeters
        }
    }

    // MARK: - Private Binary Helpers

    @inline(__always)
    private static func matchesFilterRaw(ptr: UnsafePointer<UInt8>, filter: AccidentFilter, latestYear: UInt16) -> Bool {
        let year = UInt16(ptr[8]) | (UInt16(ptr[9]) << 8)
        if !filter.yearFilter.matches(year: year, latestYear: latestYear) {
            return false
        }
        let isFatal = (ptr[14] == 1 || ptr[15] > 0)
        if isFatal {
            if !filter.showFatalAccidents { return false }
        } else if ptr[16] >= 2 {
            if !filter.showMultipleInjuryAccidents { return false }
        } else {
            if !filter.showSingleInjuryAccidents { return false }
        }

        switch filter.severity {
        case .all: break
        case .fatalOnly: if !isFatal { return false }
        case .injuryOnly: if isFatal { return false }
        }

        let isNight = ptr[18] >= 20
        switch filter.timeOfDay {
        case .all: break
        case .daytime: if isNight { return false }
        case .nighttime: if !isNight { return false }
        }

        if !filter.accidentType.matches(code: ptr[22]) {
            return false
        }
        if !filter.weather.matches(code: ptr[17]) {
            return false
        }
        return true
    }

    @inline(__always)
    private static func decodeRecord(at ptr: UnsafePointer<UInt8>, id: Int) -> AccidentRecord {
        let latE6 = readInt32LE(ptr: ptr, offset: 0)
        let lonE6 = readInt32LE(ptr: ptr, offset: 4)
        let year = UInt16(ptr[8]) | (UInt16(ptr[9]) << 8)

        return AccidentRecord(
            id: id,
            latitude: Double(latE6) / 1_000_000.0,
            longitude: Double(lonE6) / 1_000_000.0,
            year: year,
            month: ptr[10],
            day: ptr[11],
            hour: ptr[12],
            minute: ptr[13],
            severityCode: ptr[14],
            deaths: ptr[15],
            injuries: ptr[16],
            weatherCode: ptr[17],
            dayNightCode: ptr[18],
            roadSurfaceCode: ptr[19],
            roadShapeCode: ptr[20],
            signalCode: ptr[21],
            accidentTypeCode: ptr[22],
            weekdayCode: ptr[23],
            holidayCode: ptr[24],
            partyACode: ptr[25],
            partyBCode: ptr[26],
            ageACode: ptr[27],
            ageBCode: ptr[28],
            prefectureCode: ptr[29],
            injuryACode: ptr[30],
            injuryBCode: ptr[31]
        )
    }

    @inline(__always)
    private static func readInt32LE(ptr: UnsafePointer<UInt8>, offset: Int) -> Int32 {
        let b0 = UInt32(ptr[offset])
        let b1 = UInt32(ptr[offset + 1]) << 8
        let b2 = UInt32(ptr[offset + 2]) << 16
        let b3 = UInt32(ptr[offset + 3]) << 24
        return Int32(bitPattern: b0 | b1 | b2 | b3)
    }

    private static func readUInt32LE(from data: Data, offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
