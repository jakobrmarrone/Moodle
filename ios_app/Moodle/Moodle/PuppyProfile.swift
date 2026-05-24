import Foundation
import UIKit
import Combine

// MARK: - Model

struct PuppyProfile: Codable {
    var dogName: String = ""
    var ownerName: String = ""
    var breed: String = ""
    var weightLbs: Double? = nil
    var dateOfBirth: Date? = nil
    var sex: DogSex = .unknown
    var isNeutered: Bool = false
    var vetName: String = ""
    var vetPhone: String = ""
    var medicalNotes: String = ""

    enum DogSex: String, Codable, CaseIterable, Identifiable {
        case unknown = "Unknown"
        case male    = "Male"
        case female  = "Female"
        var id: String { rawValue }
    }

    /// Computed age string from dateOfBirth
    var ageString: String? {
        guard let dob = dateOfBirth else { return nil }
        let components = Calendar.current.dateComponents([.year, .month], from: dob, to: Date())
        let years  = components.year  ?? 0
        let months = components.month ?? 0
        if years > 0 {
            return months > 0 ? "\(years) yr \(months) mo" : "\(years) yr"
        } else if months > 0 {
            return "\(months) mo"
        } else {
            return "< 1 month"
        }
    }
}

// MARK: - Store

@MainActor
final class PuppyProfileStore: ObservableObject {
    @Published var profile = PuppyProfile()
    @Published var photo: UIImage? = nil

    private let defaultsKey = "puppy_profile_v1"
    private var photoURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("puppy_profile_photo.jpg")
    }

    init() {
        load()
    }

    func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        if let img = photo, let jpeg = img.jpegData(compressionQuality: 0.85) {
            try? jpeg.write(to: photoURL)
        }
    }

    func deletePhoto() {
        photo = nil
        try? FileManager.default.removeItem(at: photoURL)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(PuppyProfile.self, from: data) {
            profile = saved
        }
        if let data = try? Data(contentsOf: photoURL) {
            photo = UIImage(data: data)
        }
    }
}
