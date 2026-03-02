import Foundation

enum PreviewHelper {
    static func placeholderJPEG() -> Data {
        let base64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxISEhUREhIVFhUVFhUVFRUVFRUVFRUWFhUVFRUYHSggGBolHRUVITEhJSkrLi4uFx8zODMtNygtLisBCgoKDg0OGxAQGy0lHyUtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLf/AABEIAAEAAQMBIgACEQEDEQH/xAAbAAACAwEBAQAAAAAAAAAAAAADBAACBQYBB//EADYQAAEDAwIEBAMHAQAAAAAAAAEAAgMEBREGEiExQVFhByJxgZGh8BMyQrHB0eHhFSQkUqL/xAAYAQEBAQEBAAAAAAAAAAAAAAAAAQIDBP/EAB8RAQEBAAIDAQAAAAAAAAAAAAABAhEDIRIxQVEycf/aAAwDAQACEQMRAD8A7sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/Z"
        return Data(base64Encoded: base64) ?? Data()
    }

    static func defaultText(page: Int) -> String {
        "Texte d'aperçu indisponible - page \(page)."
    }

    static func isDefaultText(_ value: String, page: Int) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines) == defaultText(page: page)
    }
}
