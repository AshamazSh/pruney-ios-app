import SwiftUI

struct ReviewFiltersView: View {
    var onReturnToLibrary: (Bool) -> Void = { _ in }
    @State private var filters: [ReviewFilter] = []
    @State private var showingAddFilter = false
    @State private var showingReview = false
    @State private var appliedFilters: [ReviewFilter] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if filters.isEmpty {
                    ContentUnavailableView("No filters yet", systemImage: "line.3.horizontal.decrease",
                                           description: Text("Add a filter to choose what to review."))
                } else {
                    Text("Match all conditions in a tile, or any tile below.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                        if index > 0 {
                            Text("OR").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Text(filter.summary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                filters.removeAll { $0.id == filter.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove filter: \(filter.summary)")
                            .accessibilityIdentifier("filters.remove.\(filter.id)")
                        }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { showingAddFilter = true } label: {
                    Label("Add", systemImage: "plus").frame(maxWidth: .infinity)
                }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("filters.add")
                Button {
                    appliedFilters = filters
                    showingReview = true
                } label: {
                    Text("Apply").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(PruneyStyle.onAccent)
                .disabled(filters.isEmpty)
                .accessibilityIdentifier("filters.apply")
            }
            .fontWeight(.semibold)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.regularMaterial)
        }
        .navigationDestination(isPresented: $showingAddFilter) {
            NewReviewFilterView { filters.append($0) }
        }
        .navigationDestination(isPresented: $showingReview) {
            SwipeReviewView(filters: appliedFilters, onReturnToLibrary: onReturnToLibrary)
        }
    }
}

private struct NewReviewFilterView: View {
    let onAdd: (ReviewFilter) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typeEnabled = false
    @State private var dateEnabled = false
    @State private var sizeEnabled = false
    @State private var category = MediaCategory.photo
    @State private var dateRule = FilterDateRule.from
    @State private var date = Date()
    @State private var sizeRule = FilterSizeRule.greater
    @State private var sizeMegabytes = 50.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                criterion("Type", enabled: $typeEnabled) {
                    selectionMenu("Media type", selection: $category,
                                  values: MediaCategory.allCases, title: { $0.title })
                    .accessibilityIdentifier("filter.type")
                }
                criterion("Date", enabled: $dateEnabled) {
                    selectionMenu("Date condition", selection: $dateRule,
                                  values: FilterDateRule.allCases, title: { $0.title })
                    DatePicker("Creation date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("filter.date")
                }
                criterion("Size", enabled: $sizeEnabled) {
                    selectionMenu("Size condition", selection: $sizeRule,
                                  values: FilterSizeRule.allCases, title: { $0.title })
                    Text(ReviewFilter.sizeLabel(Int(sizeMegabytes)))
                        .font(.headline).monospacedDigit()
                    Slider(value: $sizeMegabytes, in: 1...1_000, step: 1)
                        .accessibilityLabel("File size threshold")
                        .accessibilityValue(ReviewFilter.sizeLabel(Int(sizeMegabytes)))
                        .accessibilityIdentifier("filter.size")
                    HStack {
                        Text("1 MB")
                        Spacer()
                        Text("1 GB")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Text("Enable at least one condition. Dates include the selected day. Size uses accessible local files; items with incomplete size measurements cannot match a size condition.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("New filter")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onAdd(ReviewFilter(category: typeEnabled ? category : nil,
                                   dateRule: dateRule, date: dateEnabled ? date : nil,
                                   sizeRule: sizeRule, sizeMegabytes: sizeEnabled ? Int(sizeMegabytes) : nil))
                dismiss()
            } label: {
                Text("Add").frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .foregroundStyle(PruneyStyle.onAccent)
            .controlSize(.large)
            .disabled(!typeEnabled && !dateEnabled && !sizeEnabled)
            .accessibilityIdentifier("filter.add")
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.regularMaterial)
        }
    }

    private func selectionMenu<Value: Hashable>(_ label: String, selection: Binding<Value>,
                                               values: [Value], title: @escaping (Value) -> String) -> some View {
        Menu {
            Picker(label, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(title(value)).tag(value)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title(selection.wrappedValue))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(title(selection.wrappedValue))
    }

    private func criterion<Content: View>(_ title: String, enabled: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { enabled.wrappedValue.toggle() } label: {
                Image(systemName: enabled.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(enabled.wrappedValue ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) condition")
            .accessibilityValue(enabled.wrappedValue ? "Enabled" : "Disabled")
            .accessibilityIdentifier("filter.enable.\(title.lowercased())")
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline)
                    .frame(minHeight: 44, alignment: .center)
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                    .disabled(!enabled.wrappedValue)
                    .opacity(enabled.wrappedValue ? 1 : 0.4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
