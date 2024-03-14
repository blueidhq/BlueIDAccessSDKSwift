#if os(iOS) || os(watchOS)
import SwiftUI

internal enum BlueModalStatus {
    case Waiting
    case Success
    case Failed
}

internal class BlueAccessDeviceModalViewModel: ObservableObject {
    @Published var title = ""
    @Published var message = ""
    @Published var status: BlueModalStatus = .Waiting
    
    @Published var showDismissButton = true
    
    init(title: String = "", message: String = "", status: BlueModalStatus? = nil) {
        self.title = title
        self.message = message
        self.status = status ?? .Waiting
    }
    
    var symbol: String {
        switch(status) {
        case .Waiting:
            return "wifi"
            
        case .Success:
            return "checkmark.circle"
            
        case .Failed:
            return "exclamationmark.circle"
        }
    }
    
    var symbolColor: Color {
        switch(status) {
        case .Waiting, .Success:
            return .blue
            
        case .Failed:
            return .red
        }
    }
}

internal struct BlueAccessDeviceModalView: View {
    @ObservedObject private var vm: BlueAccessDeviceModalViewModel
    
    internal var height: CGFloat = 350
    internal var backgroundColor: UIColor = .white
    internal var foregroundColor: UIColor = .black
    
    private let onDismiss: () -> Void
    private let cornerRadius: CGFloat = 35
    
    public init(
        _ vm: BlueAccessDeviceModalViewModel,
        _ onDismiss: @escaping () -> Void)
    {
        self.vm = vm
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    Spacer()
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .foregroundColor(Color(backgroundColor))
                            .shadow(color: .gray, radius: 1)
                        
                        VStack(alignment: .center) {
                            Text(vm.title)
                                .font(.system(size: 20))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            VStack() {
                                if #available(iOS 17.0, *) {
                                    Image(systemName: vm.symbol)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 100)
                                        .foregroundColor(vm.symbolColor)
                                        .symbolEffect(.variableColor.cumulative.dimInactiveLayers.nonReversing, options: .speed(3), isActive: vm.status == .Waiting)
                                        .contentTransition(.symbolEffect(.replace.offUp.wholeSymbol))
                                } else {
                                    switch (vm.status) {
                                        case .Waiting:
                                            if #available(iOS 15.0, *) {
                                                ProgressView()
                                                    .controlSize(.large)
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                            } else {
                                                ProgressView()
                                                    .scaleEffect(x: 2, y: 2, anchor: .center)
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                            }
                                            
                                        case .Success:
                                            Image(systemName: "checkmark.circle")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxHeight: 100)
                                                .foregroundColor(.blue)
                                            
                                        case .Failed:
                                            Image(systemName: "exclamationmark.circle")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxHeight: 100)
                                                .foregroundColor(.red)
                                    }
                                }
                                
                                Text(vm.message)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 12))
                                    .padding(.top, 20)
                                    .hidden(vm.message.isEmpty)
                            }
                            
                            Spacer()
                            
                            Button {
                                onDismiss()
                            } label: {
                                Text(blueI18n.cmnCancelLabel)
                                    .font(.system(size: 18))
                                    .frame(maxWidth: .infinity)
                                    .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                                    .background(Color.gray.opacity(0.5))
                                    .cornerRadius(10)
                            }
                            .hidden(!vm.showDismissButton)
                        }
                        .padding(30)
                    }
                    .frame(height: height + cornerRadius)
                    .offset(y: cornerRadius - 15)
                    .padding(.horizontal, 15)
                }
                .foregroundColor(Color(foregroundColor))
                
            }
        }
    }
}

@available(iOS 16.0, *)
struct BlueAccessDeviceModalView_Preview: PreviewProvider {
    static var previews: some View {
        BlueAccessDeviceModalView(
            BlueAccessDeviceModalViewModel(
                title: "Unlocking in Progress",
                message: "Establishing secure connection..."
            )
        ) {}
        
        BlueAccessDeviceModalView(
            BlueAccessDeviceModalViewModel(
                title: "Access Granted",
                message: "Please proceed.",
                status: .Success
            )
        ) {}
        
        BlueAccessDeviceModalView(
            BlueAccessDeviceModalViewModel(
                title: "Access Denied",
                message: "Credentials are not valid at this time and/or day of the week.",
                status: .Failed
            )
        ) {}
    }
}
#endif
