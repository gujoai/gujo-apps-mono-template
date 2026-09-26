import SwiftUI
import __NAME__Core

struct ContentView: View {
    let model: ItemListModel
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            List(model.items) { item in
                Toggle(isOn: doneBinding(for: item)) {
                    Text(item.title)
                }
                .contextMenu {
                    Button("삭제", role: .destructive) {
                        model.remove(item)
                    }
                }
            }
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top])
            }
            HStack {
                TextField("새 항목", text: $newTitle)
                    .onSubmit(add)
                Button("추가", action: add)
            }
            .padding()
        }
        .frame(minWidth: 360, minHeight: 320)
        .toolbar {
            Button("새로고침", systemImage: "arrow.clockwise") {
                model.reload()
            }
        }
    }

    private func doneBinding(for item: Item) -> Binding<Bool> {
        Binding(
            get: { item.isDone },
            set: { model.setDone(item, $0) }
        )
    }

    private func add() {
        if model.add(title: newTitle) {
            newTitle = ""
        }
    }
}
