import Foundation

extension TimeInterval {
    /// 格式化为 "12m" 或 "2h 30m"，忽略秒数。
    var formattedElapsedTime: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
