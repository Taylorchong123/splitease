import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ticket.dart';

class TicketRepository {
  TicketRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _tickets => _db.collection('tickets');

  /// Tickets the user owns or was invited to (matched by email).
  Stream<List<Ticket>> watchFor({required String uid, required String email}) {
    final query = _tickets.where(
      Filter.or(
        Filter('ownerId', isEqualTo: uid),
        Filter('memberEmails', arrayContains: email.toLowerCase()),
      ),
    );
    return query.snapshots().map((snap) {
      final list = snap.docs.map((d) => Ticket.fromMap(d.id, d.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<Ticket?> watchOne(String id) => _tickets.doc(id).snapshots().map(
        (d) => d.exists ? Ticket.fromMap(d.id, d.data()!) : null,
      );

  Future<String> create(Ticket ticket) async {
    final ref = _tickets.doc();
    await ref.set(ticket.toMap());
    return ref.id;
  }

  Future<void> save(Ticket ticket) => _tickets.doc(ticket.id).set(ticket.toMap());

  Future<void> delete(String id) => _tickets.doc(id).delete();

  /// Queues one notification per unpaid participant with their full itemized breakdown.
  /// A Cloud Function (see functions/index.js) delivers them via push / email.
  Future<void> queueNotifications(Ticket ticket) async {
    final batch = _db.batch();
    final owner = ticket.participants.firstWhere(
      (p) => p.isOwner,
      orElse: () => ticket.participants.first,
    );

    for (final p in ticket.participants.where((p) => !p.isOwner && !p.paid)) {
      final pEmail = p.email.toLowerCase();

      final assignedItems = ticket.items.where((i) {
        return i.assignedEmails.isEmpty ||
            i.assignedEmails.contains(pEmail);
      }).map((i) {
        final assignedCount = i.assignedEmails.isEmpty
            ? ticket.participants.length
            : i.assignedEmails.length;
        final pItemTotal = i.total ~/ (assignedCount > 0 ? assignedCount : 1);
        return {
          'name': i.name,
          'quantity': i.quantity,
          'unitPrice': i.amount,
          'itemTotal': i.total,
          'pShare': pItemTotal,
          'sharedWithCount': assignedCount,
        };
      }).toList();

      batch.set(_db.collection('notifications').doc(), {
        'ticketId': ticket.id,
        'title': ticket.title,
        'toName': p.name,
        'toEmail': pEmail,
        'ownerName': owner.name,
        'ownerEmail': owner.email,
        'amount': p.share,
        'currency': ticket.currency,
        'subtotal': ticket.subtotal,
        'tax': ticket.tax,
        'items': assignedItems,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
