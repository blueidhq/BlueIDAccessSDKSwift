#if os(iOS) || os(watchOS)
import SwiftUI
import Combine

private func getColor(_ status: BlueTaskStatus) -> Color {
    switch (status) {
        case .ready, .started, .skipped:
            return .gray
        case .failed:
            return .red
        case .succeeded:
            return .green
    }
}

private func getLineColor(_ status: BlueTaskStatus) -> Color {
    switch (status) {
        case .ready, .started:
            return .gray
        case .failed:
            return .red
        case .succeeded, .skipped:
            return .green
    }
}

private func getSymbol(_ status: BlueTaskStatus) -> String {
    switch(status) {
        case .ready:
            return "circle"
        case .started:
            return "circle.circle"
        case .failed:
            return "xmark.circle"
        case .succeeded, .skipped:
            return "checkmark.circle"
    }
}

class BlueTaskModel: ObservableObject, Identifiable {
    @Published var label: String
    @Published var status: BlueTaskStatus
    @Published var statusColor: Color
    @Published var lineColor: Color
    @Published var symbol: String
    @Published var errorDescription: String
    @Published var isLast: Bool
    
    private var subscriber: AnyCancellable?
    
    init(_ task: BlueTask, _ isLast: Bool) {
        self.label = task.label
        self.status = task.status.value
        self.statusColor = getColor(task.status.value)
        self.lineColor = getLineColor(task.status.value)
        self.symbol = getSymbol(task.status.value)
        self.errorDescription = task.errorDescription ?? ""
        self.isLast = isLast
        
        self.subscriber = task.status.sink{ [weak self] status in
            guard let self = self else { return }
            
            self.status = status
            self.statusColor = getColor(status)
            self.lineColor = getLineColor(status)
            self.symbol = getSymbol(status)
            self.errorDescription = task.errorDescription ?? ""
            
            self.objectWillChange.send()
        }
    }
}

struct TaskView: View {
    @StateObject var task: BlueTaskModel
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center){
                if (task.status == .started) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                        .padding(.leading, 2)
                        .padding(.trailing, 2)
                } else {
                    Image(systemName: task.symbol)
                        .foregroundColor(task.statusColor)
                        .font(.system(size: 20))
                }
                
                Text(task.label)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(alignment: .center) {
                if !task.isLast {
                    Rectangle()
                        .fill(task.lineColor)
                        .frame(width: 2)
                        .padding(.horizontal, 10.5)
                }
                
                if !task.errorDescription.isEmpty {
                    Text(task.errorDescription)
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                        .padding(.vertical, 2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

class BlueSynchronizeAccessDeviceModalViewModel: ObservableObject {
    @Published var title = ""
    @Published var dismiss: String = ""
    @Published var dismissEnabled: Bool = true
    @Published var tasks: [BlueTask]
    
    init(title: String = "", dismiss: String = "", tasks: [BlueTask] = []) {
        self.title = title
        self.dismiss = dismiss
        self.tasks = tasks
    }
}

struct BlueSynchronizeAccessDeviceModalView: View {
    @ObservedObject private var vm: BlueSynchronizeAccessDeviceModalViewModel
    
    internal var height: CGFloat = 500
    internal var backgroundColor: UIColor = .white
    internal var foregroundColor: UIColor = .black
    
    private let onDismiss: () -> Void
    private let cornerRadius: CGFloat = 35
    
    public init(
        _ vm: BlueSynchronizeAccessDeviceModalViewModel,
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
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(vm.tasks.indices, id: \.self){ index in
                                        TaskView(task: BlueTaskModel(vm.tasks[index], index == vm.tasks.indices.last))
                                    }
                                }.padding(.vertical, 10)
                            }
                            
                            if !vm.dismiss.isEmpty {
                                Spacer()
                                
                                Button {
                                    onDismiss()
                                } label: {
                                    Text(vm.dismiss)
                                        .font(.system(size: 18))
                                        .frame(maxWidth: .infinity)
                                        .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                                        .background(Color.gray.opacity(0.5))
                                        .cornerRadius(10)
                                }
                                .disabled(!vm.dismissEnabled)
                            }
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

struct BlueSynchronizeAccessDeviceModalView_Preview: PreviewProvider {
    static var previews: some View {
        BlueSynchronizeAccessDeviceModalView(
            BlueSynchronizeAccessDeviceModalViewModel(
                title: "Synchronization in Progress",
                dismiss: "Cancel",
                tasks: [
                    BlueTask(
                        id: "A",
                        label: "Retrieve device configuration",
                        status: .failed,
                        error: BlueError(.sdkCredentialNotFound, cause: BlueError(.invalidCrc), detail: "Something is wrong")
                    ) { _ in .result(nil) },
                    
                    BlueTask(
                        id: "B",
                        label: "Update device configuration",
                        status: .succeeded
                    ) { _ in .result(nil) },
                    
                    BlueTask(
                        id: "C",
                        label: "Wait for device to restart",
                        status: .started
                    ) { _ in .result(nil) },
                    
                    BlueTask(
                        id: "D",
                        label: "Push system status",
                        status: .ready
                    ) { _ in .result(nil) }
                ]
            )
        ) {}
    }
}
#endif
