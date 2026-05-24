import SwiftUI
import PhotosUI

struct PuppyProfileView: View {
    @EnvironmentObject var store: PuppyProfileStore
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                photoHeader
                if store.profile.dogName.isEmpty && !isEditing {
                    emptyState
                } else {
                    profileCards
                }
            }
            .padding()
        }
        .navigationTitle("Puppy Profile")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { store.save() }
                    isEditing.toggle()
                }
                .font(.body.bold())
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                PuppyProfileEditView()
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Photo header

    private var photoHeader: some View {
        VStack(spacing: 12) {
            if let img = store.photo {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                    .shadow(radius: 4)
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color(.systemGray3))
                    )
            }

            if !store.profile.dogName.isEmpty {
                Text(store.profile.dogName)
                    .font(.title.bold())
                if !store.profile.breed.isEmpty {
                    Text(store.profile.breed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Profile cards

    private var profileCards: some View {
        VStack(spacing: 16) {
            // Basic info card
            profileCard(title: "About") {
                infoRow(icon: "person.fill",       label: "Owner",    value: store.profile.ownerName)
                if let age = store.profile.ageString {
                    infoRow(icon: "calendar",      label: "Age",      value: age)
                }
                infoRow(icon: "scalemass.fill",    label: "Weight",   value: weightText)
                infoRow(icon: "pawprint",          label: "Sex",      value: sexText)
            }

            // Health card
            profileCard(title: "Health") {
                infoRow(icon: "cross.fill",        label: "Vet",      value: store.profile.vetName)
                if !store.profile.vetPhone.isEmpty {
                    infoRow(icon: "phone.fill",    label: "Phone",    value: store.profile.vetPhone)
                }
                if !store.profile.medicalNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.profile.medicalNotes)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var weightText: String {
        guard let w = store.profile.weightLbs else { return "—" }
        return String(format: "%.1f lbs", w)
    }

    private var sexText: String {
        let base = store.profile.sex.rawValue
        guard store.profile.sex != .unknown else { return base }
        return store.profile.isNeutered ? "\(base) (neutered/spayed)" : base
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No profile yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap Edit to add your dog's info.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Button("Set Up Profile") { isEditing = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private func profileCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        guard !value.isEmpty && value != "—" else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.subheadline)
                }
                Spacer()
            }
        )
    }
}

// MARK: - Edit sheet

struct PuppyProfileEditView: View {
    @EnvironmentObject var store: PuppyProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem? = nil

    var body: some View {
        Form {
            // Photo section
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if let img = store.photo {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Image(systemName: "pawprint.fill")
                                            .font(.system(size: 36))
                                            .foregroundStyle(Color(.systemGray3))
                                    )
                            }
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task { @MainActor in
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                store.photo = img
                            }
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)

                if store.photo != nil {
                    Button("Remove Photo", role: .destructive) {
                        store.deletePhoto()
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Dog info
            Section("Dog Info") {
                LabeledContent("Name") {
                    TextField("e.g. Moodle", text: $store.profile.dogName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Breed") {
                    TextField("e.g. Labrador", text: $store.profile.breed)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Sex", selection: $store.profile.sex) {
                    ForEach(PuppyProfile.DogSex.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                if store.profile.sex != .unknown {
                    Toggle("Neutered / Spayed", isOn: $store.profile.isNeutered)
                }
                LabeledContent("Weight (lbs)") {
                    TextField("e.g. 45.0", value: $store.profile.weightLbs, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                DatePicker(
                    "Date of Birth",
                    selection: Binding(
                        get: { store.profile.dateOfBirth ?? Calendar.current.date(byAdding: .year, value: -2, to: Date())! },
                        set: { store.profile.dateOfBirth = $0 }
                    ),
                    displayedComponents: .date
                )
                // Toggle to clear DOB
                if store.profile.dateOfBirth != nil {
                    Button("Clear Date of Birth", role: .destructive) {
                        store.profile.dateOfBirth = nil
                    }
                }
            }

            // Owner info
            Section("Owner") {
                LabeledContent("Owner Name") {
                    TextField("Your name", text: $store.profile.ownerName)
                        .multilineTextAlignment(.trailing)
                }
            }

            // Vet info
            Section("Veterinarian") {
                LabeledContent("Vet / Clinic") {
                    TextField("e.g. Happy Paws Vet", text: $store.profile.vetName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Phone") {
                    TextField("555-555-5555", text: $store.profile.vetPhone)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.phonePad)
                }
            }

            // Medical notes
            Section("Medical Notes") {
                TextEditor(text: $store.profile.medicalNotes)
                    .frame(minHeight: 80)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.save()
                    dismiss()
                }
                .font(.body.bold())
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PuppyProfileView()
            .environmentObject(PuppyProfileStore())
    }
}
