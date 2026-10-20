import SwiftUI

struct CameraReadoutView: View {
    let readout: CameraReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("현재 ISO \(readout.iso.formatted(.number.precision(.fractionLength(0)))) · \(shutterText) · EV \(readout.exposureBias.formatted(.number.precision(.fractionLength(1))))")
            Text("초점 \(readout.lensPosition.formatted(.number.precision(.fractionLength(2))))")
            if let kelvin = readout.kelvin, let tint = readout.tint {
                Text("WB \(kelvin.formatted(.number.precision(.fractionLength(0)))) K · Tint \(tint.formatted(.number.precision(.fractionLength(1))))")
            }
            if readout.isAdjusting { Text("자동 조정 중").foregroundStyle(.yellow) }
        }
        .font(.caption2.monospacedDigit())
        .accessibilityElement(children: .combine)
    }

    private var shutterText: String {
        if readout.shutterSeconds < 1 {
            return "1/\((1 / readout.shutterSeconds).formatted(.number.precision(.fractionLength(0)))) s"
        }
        return "\(readout.shutterSeconds.formatted(.number.precision(.fractionLength(2)))) s"
    }
}
