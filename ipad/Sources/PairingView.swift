import SwiftUI
import VisionKit

struct PairingView: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var scanning = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VoltView(mood: .idle, size: 150)
                    .padding(.top, 40)
                VStack(spacing: 10) {
                    Text("Empareja tu iPad")
                        .font(.largeTitle.bold())
                    Text("VoltaDock en el iPad te enseña tus sesiones de Claude Code y te deja aprobar permisos sin ir al ordenador.")
                        .font(.title3)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }

                Card {
                    step(1, "En tu ordenador abre VoltaDock → Ajustes → iPad y activa «Permitir iPad».")
                    step(2, "Pulsa «Emparejar iPad…». Aparece un código QR.")
                    step(3, "Escanéalo aquí. El iPad y el ordenador tienen que estar en la misma red Wi‑Fi.")
                }
                .frame(maxWidth: 560)

                VStack(spacing: 14) {
                    if DataScannerViewController.isSupported {
                        Button {
                            scanning = true
                        } label: {
                            Label("Escanear código", systemImage: "qrcode.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.black)
                    }

                    HStack {
                        TextField("o pega el código voltadock://…", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        Button("Conectar") { model.pair(with: code) }
                            .buttonStyle(.bordered)
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if let error = model.pairingError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Theme.deny)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 560)

                Text("Todo va cifrado y solo por tu red local: no pasa por ningún servidor.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $scanning) {
            QRScannerSheet { text in
                scanning = false
                model.pair(with: text)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Theme.amber, in: Circle())
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - QR scanner

struct QRScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScanner(onCode: onCode)
                .ignoresSafeArea()
                .navigationTitle("Escanea el código")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                }
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue,
                   text.hasPrefix("voltadock://"), !done {
                    done = true
                    dataScanner.stopScanning()
                    onCode(text)
                    return
                }
            }
        }
    }
}
