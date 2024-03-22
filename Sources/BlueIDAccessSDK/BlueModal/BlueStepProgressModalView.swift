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

private func getTextColor(_ status: BlueTaskStatus) -> Color {
    switch (status) {
        case .ready, .started, .skipped:
            return .black
        case .succeeded:
            return Color(red: 0.0, green: 0.5, blue: 0.0)
        default:
            return getColor(status)
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
        case .succeeded:
            return "checkmark.circle"
        case .skipped:
            return "minus.circle"
    }
}

class BlueTaskModel: ObservableObject, Identifiable {
    @Published var label: String
    @Published var status: BlueTaskStatus
    @Published var progress: Float?
    @Published var statusColor: Color
    @Published var textColor: Color
    @Published var symbol: String
    @Published var errorDescription: String
    @Published var isLast: Bool
    
    private var statusSubscriber: AnyCancellable?
    private var progressSubscriber: AnyCancellable?
    
    init(_ task: BlueTask, _ isLast: Bool) {
        self.label = task.label
        self.status = task.status.value
        self.progress = task.progress?.value
        self.textColor = getTextColor(task.status.value)
        self.statusColor = getColor(task.status.value)
        self.symbol = getSymbol(task.status.value)
        self.errorDescription = task.errorDescription ?? ""
        self.isLast = isLast
        
        self.statusSubscriber = task.status.sink{ [weak self] status in
            guard let self = self else { return }
            
            self.status = status
            self.textColor = getTextColor(status)
            self.statusColor = getColor(status)
            self.symbol = getSymbol(status)
            self.errorDescription = task.errorDescription ?? ""
            
            self.objectWillChange.send()
        }
        
        self.progressSubscriber = task.progress?.sink{ [weak self] progress in
            guard let self = self else { return }
            
            self.progress = progress
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
                    .foregroundColor(task.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(task.statusColor)
                        .frame(width: 2)
                        .padding(.horizontal, 10.5)
                        .hidden(task.isLast)
                    
                    if !task.errorDescription.isEmpty {
                        Text(task.errorDescription)
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                            .padding(.leading, 32)
                            .padding(.bottom, 5)
                            .fixedSize(horizontal: false, vertical: true)
                            .alignmentGuide(.leading) { d in d[.leading] }
                    } else {
                        if task.status == .started && task.progress != nil {
                            ProgressView(value: task.progress, total: 100)
                                .padding(.leading, 32)
                                .alignmentGuide(.leading) { d in d[.leading] }
                        }
                    }
                }
            }
        }
    }
}

class BlueStepProgressModalViewModel: ObservableObject {
    @Published var title = ""
    @Published var dismiss: String = ""
    @Published var dismissEnabled: Bool = true
    @Published var tasks: [BlueTask]
    
    init(title: String = "", dismiss: String = "", dismissEnabled: Bool = true, tasks: [BlueTask] = []) {
        self.title = title
        self.dismiss = dismiss
        self.dismissEnabled = dismissEnabled
        self.tasks = tasks
    }
}

struct BlueStepProgressModalView: View {
    @ObservedObject private var vm: BlueStepProgressModalViewModel
    
    internal var height: CGFloat = 550
    internal var backgroundColor: UIColor = .white
    internal var foregroundColor: UIColor = .black
    
    private let onDismiss: () -> Void
    private let cornerRadius: CGFloat = 35
    
    public init(
        _ vm: BlueStepProgressModalViewModel,
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
                        
                        VStack(alignment: .center, spacing: 0) {
                            Text(vm.title)
                                .font(.system(size: 20))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            
                            Spacer()
                            
                            GeometryReader { geometry in
                                ScrollView(.vertical) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(vm.tasks.indices, id: \.self){ index in
                                            TaskView(task: BlueTaskModel(vm.tasks[index], index == vm.tasks.indices.last))
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .frame(width: geometry.size.width)
                                    .frame(minHeight: geometry.size.height)
                                }
                            }
                            
                            Spacer()
                            
                            if !vm.dismiss.isEmpty {
                                Button {
                                    onDismiss()
                                } label: {
                                    Text(vm.dismiss)
                                        .font(.system(size: 18))
                                        .frame(maxWidth: .infinity)
                                        .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                                        .background(Color.gray.opacity(vm.dismissEnabled ? 0.5 : 0.3))
                                        .foregroundColor(vm.dismissEnabled ? .black : .gray)
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

let noop: (BlueTask, BlueSerialTaskRunner) async throws -> BlueTaskResult = { _, _ in .result(nil) }

struct BlueSynchronizeAccessDeviceModalView_Preview: PreviewProvider {
    static var previews: some View {
        BlueStepProgressModalView(
            BlueStepProgressModalViewModel(
                title: "Synchronization has failed (Worst case)",
                dismiss: "Done",
                tasks: Array(1..<12).map { element in
                    BlueTask(
                        id: element.description,
                        label: "Task label - \(element.description)",
                        status: .failed,
                        error: BlueError(.sdkDecodeJsonFailed, cause: BlueError(.sdkNetworkError), detail: "Something went wrong ¯\\_(ツ)_/¯"),
                        handler: noop
                    )
                }
            )
        ) {}
        
        BlueStepProgressModalView(
            BlueStepProgressModalViewModel(
                title: "Cancelling...",
                dismiss: "Cancel",
                dismissEnabled: false,
                tasks: Array(1..<12).enumerated().map { (index, element) in
                    BlueTask(
                        id: element.description,
                        label: "Task label - \(element.description)",
                        status: index == 1 ? .failed : .succeeded,
                        error: index == 1 ? BlueError(.sdkDecodeJsonFailed, cause: BlueError(.sdkNetworkError), detail: "Something went wrong ¯\\_(ツ)_/¯"): nil,
                        handler: noop
                    )
                }
            )
        ) {}
    }
}
#endif
