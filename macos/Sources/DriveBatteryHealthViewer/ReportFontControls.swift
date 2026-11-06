import SwiftUI

struct ReportFontControls: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 4) {
            Button(action: model.decreaseReportTextSize) { Image(systemName: "minus").frame(width: 12, height: 12) }
                .disabled(model.reportTextSize <= 11)
                .help(model.t("decreaseReportFont"))
                .accessibilityLabel(model.t("decreaseReportFont"))
                .accessibilityIdentifier("DBHV.ReportFont.Smaller")
            Button(action: model.resetReportTextSize) {
                Text("\(Int(model.reportTextSize)) pt").monospacedDigit().frame(minWidth: 34)
            }
            .help(model.t("resetReportFont"))
            .accessibilityLabel(model.t("resetReportFont"))
            .accessibilityValue(Text("\(Int(model.reportTextSize)) pt"))
            .accessibilityIdentifier("DBHV.ReportFont.Reset")
            Button(action: model.increaseReportTextSize) { Image(systemName: "plus").frame(width: 12, height: 12) }
                .disabled(model.reportTextSize >= 22)
                .help(model.t("increaseReportFont"))
                .accessibilityLabel(model.t("increaseReportFont"))
                .accessibilityIdentifier("DBHV.ReportFont.Larger")
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }
}
