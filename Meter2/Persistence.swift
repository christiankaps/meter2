import SwiftData

protocol PersistenceContextCommitting: AnyObject {
    func save() throws
    func rollback()
}

extension ModelContext: PersistenceContextCommitting {}

enum PersistenceCommitter {
    static func commit(
        using context: PersistenceContextCommitting,
        changes: () -> Void
    ) -> Result<Void, Error> {
        changes()
        return savePendingChanges(using: context)
    }

    static func savePendingChanges(
        using context: PersistenceContextCommitting
    ) -> Result<Void, Error> {
        do {
            try context.save()
            return .success(())
        } catch {
            context.rollback()
            return .failure(error)
        }
    }
}
