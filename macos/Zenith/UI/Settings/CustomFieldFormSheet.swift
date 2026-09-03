import SwiftUI
import ZenithData

/// Port of `field-form-dialog.tsx` — create/edit a custom field. Type is
/// fixed once created (matches the web dialog disabling the type picker in
/// edit mode); select types get an editable option-color/name list,
/// iteration gets an editable title/start-date/duration list.
struct CustomFieldFormSheet: View {
    enum Mode {
        case create
        case edit(CustomField)
    }

    let model: SpaceDetailModel
    let mode: Mode
    let onDismiss: () -> Void

    @State private var name: String
    @State private var type: CustomFieldType
    @State private var options: [FieldOption]
    @State private var iterations: [IterationOption]
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(model: SpaceDetailModel, mode: Mode, onDismiss: @escaping () -> Void) {
        self.model = model
        self.mode = mode
        self.onDismiss = onDismiss
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _type = State(initialValue: .text)
            _options = State(initialValue: [])
            _iterations = State(initialValue: [])
        case .edit(let field):
            _name = State(initialValue: field.name)
            _type = State(initialValue: field.type)
            _options = State(initialValue: field.options.fieldOptions)
            _iterations = State(initialValue: field.options.iterationOptions)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isSelectType: Bool {
        type == .singleSelect || type == .multiSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(CustomFieldType.allCases, id: \.self) { type in
                            Text(typeLabel(type)).tag(type)
                        }
                    }
                    .disabled(isEditing)
                }

                if isSelectType {
                    Section("Options") {
                        ForEach($options) { $option in
                            HStack {
                                Picker("", selection: $option.color) {
                                    ForEach(FieldColors.values, id: \.self) { color in
                                        Label(color.rawValue.capitalized, systemImage: "circle.fill")
                                            .foregroundStyle(Theme.fieldColor(color))
                                            .tag(color.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 130)
                                TextField("Option name", text: $option.name)
                                Button {
                                    options.removeAll { $0.id == option.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button {
                            options.append(FieldOption(id: UUID().uuidString, name: "", color: FieldColor.gray.rawValue))
                        } label: {
                            Label("Add option", systemImage: "plus")
                        }
                    }
                } else if type == .iteration {
                    Section("Iterations") {
                        ForEach($iterations) { $iteration in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    TextField("Title", text: $iteration.title)
                                    Button {
                                        iterations.removeAll { $0.id == iteration.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                HStack {
                                    TextField("Start date (YYYY-MM-DD)", text: $iteration.startDate)
                                    Stepper(
                                        "\(iteration.durationDays) day\(iteration.durationDays == 1 ? "" : "s")",
                                        value: $iteration.durationDays, in: 1...365
                                    )
                                }
                            }
                        }
                        Button {
                            iterations.append(
                                IterationOption(
                                    id: UUID().uuidString, title: "", startDate: "", durationDays: 14))
                        } label: {
                            Label("Add iteration", systemImage: "plus")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onDismiss)
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(isEditing ? "Edit Field" : "New Field")
    }

    private func typeLabel(_ type: CustomFieldType) -> String {
        switch type {
        case .text: return "Text"
        case .number: return "Number"
        case .date: return "Date"
        case .singleSelect: return "Single select"
        case .multiSelect: return "Multi select"
        case .iteration: return "Iteration"
        }
    }

    private var fieldOptions: FieldOptions {
        type == .iteration ? .iterations(iterations) : .fields(options)
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        switch mode {
        case .create:
            if let error = await model.createCustomField(name: name, type: type, options: fieldOptions) {
                errorMessage = error
                isSaving = false
                return
            }
        case .edit(let field):
            if let error = await model.updateCustomField(field.id, name: name, options: fieldOptions) {
                errorMessage = error
                isSaving = false
                return
            }
        }
        isSaving = false
        onDismiss()
    }
}
