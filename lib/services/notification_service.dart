import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/money.dart';
import '../models/ticket.dart';

/// Registers this device for push notifications so a Cloud Function can
/// reach the user by email address.
class NotificationService {
  static Future<void> registerDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await user.reload();
    } catch (_) {
      // Ignore network errors on reload
    }

    final updatedUser = FirebaseAuth.instance.currentUser ?? user;
    final email = updatedUser.email?.trim().toLowerCase();

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token == null) return;

    final data = <String, dynamic>{
      'fcmTokens': FieldValue.arrayUnion([token]),
    };
    if (email != null && email.isNotEmpty) {
      data['email'] = email;
    }

    await FirebaseFirestore.instance.collection('users').doc(updatedUser.uid).set(
      data,
      SetOptions(merge: true),
    );
  }

  /// Formats a complete plain-text email breakdown for a specific participant.
  static String formatEmailBreakdown(Ticket ticket, Participant participant) {
    final owner = ticket.participants.firstWhere(
      (p) => p.isOwner,
      orElse: () => ticket.participants.first,
    );
    final pEmail = participant.email.toLowerCase();

    final lines = <String>[];
    lines.add('Hi ${participant.name.isNotEmpty ? participant.name : 'there'},\n');
    lines.add('${owner.name} sent you a bill breakdown for "${ticket.title.isNotEmpty ? ticket.title : 'Bill'}".\n');
    lines.add('YOUR ITEMIZED BREAKDOWN:');

    final assignedItems = ticket.items.where((i) {
      return i.assignedEmails.isEmpty || i.assignedEmails.contains(pEmail);
    }).toList();

    if (assignedItems.isNotEmpty) {
      for (final i in assignedItems) {
        final count = i.assignedEmails.isEmpty ? ticket.participants.length : i.assignedEmails.length;
        final pShare = i.total ~/ (count > 0 ? count : 1);
        final splitInfo = count > 1 ? ' (Split with $count people)' : '';
        lines.add('• ${i.name} (${i.quantity}x)$splitInfo: ${Money.format(pShare, ticket.currency)}');
      }
    } else {
      lines.add('• Share of food subtotal');
    }

    if (ticket.tax > 0) {
      lines.add('• Proportional SST/Tax share');
    }
    if (ticket.serviceCharge > 0) {
      lines.add('• Proportional Service Charge share');
    }

    lines.add('\nTOTAL AMOUNT OWED: ${Money.format(participant.share, ticket.currency)}');
    lines.add('\nPlease pay ${owner.name} (${owner.email}).');
    lines.add('\nSent via SplitEase');

    return lines.join('\n');
  }
}
