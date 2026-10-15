import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/money.dart';

enum TicketStatus { draft, open, partiallyPaid, settled }

enum ItemType { food, beverage, modifier, discount, fee, other }

class TicketItem {
  const TicketItem({
    this.id,
    required this.name,
    required this.amount,
    this.quantity = 1,
    this.assignedEmails = const [],
    this.parentId,
    this.itemType = ItemType.food,
    this.isVoidOrComplimentary = false,
    this.confidenceScore = 1.0,
  });

  final String? id;
  final String name;

  /// Unit price in minor units.
  final int amount;
  final int quantity;

  /// List of participant emails assigned to this item.
  /// If empty, the item is shared by all participants.
  final List<String> assignedEmails;

  /// ID of parent item if this is a modifier/add-on.
  final String? parentId;

  final ItemType itemType;
  final bool isVoidOrComplimentary;
  final double confidenceScore;

  int get total => isVoidOrComplimentary ? 0 : amount * quantity;

  TicketItem copyWith({
    String? id,
    String? name,
    int? amount,
    int? quantity,
    List<String>? assignedEmails,
    String? parentId,
    ItemType? itemType,
    bool? isVoidOrComplimentary,
    double? confidenceScore,
  }) =>
      TicketItem(
        id: id ?? this.id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        quantity: quantity ?? this.quantity,
        assignedEmails: assignedEmails ?? this.assignedEmails,
        parentId: parentId ?? this.parentId,
        itemType: itemType ?? this.itemType,
        isVoidOrComplimentary: isVoidOrComplimentary ?? this.isVoidOrComplimentary,
        confidenceScore: confidenceScore ?? this.confidenceScore,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'amount': amount,
        'quantity': quantity,
        'assignedEmails': assignedEmails,
        'parentId': parentId,
        'itemType': itemType.name,
        'isVoidOrComplimentary': isVoidOrComplimentary,
        'confidenceScore': confidenceScore,
      };

  factory TicketItem.fromMap(Map<String, dynamic> m) => TicketItem(
        id: m['id'] as String?,
        name: m['name'] as String,
        amount: (m['amount'] as num).toInt(),
        quantity: (m['quantity'] as num? ?? 1).toInt(),
        assignedEmails: (m['assignedEmails'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            const [],
        parentId: m['parentId'] as String?,
        itemType: m['itemType'] != null
            ? ItemType.values.byName(m['itemType'] as String)
            : ItemType.food,
        isVoidOrComplimentary: m['isVoidOrComplimentary'] as bool? ?? false,
        confidenceScore: (m['confidenceScore'] as num? ?? 1.0).toDouble(),
      );
}

class Participant {
  const Participant({
    required this.name,
    required this.email,
    required this.share,
    required this.paid,
    this.isOwner = false,
  });

  final String name;
  final String email;
  final int share; // minor units
  final bool paid;
  final bool isOwner;

  Participant copyWith({int? share, bool? paid}) => Participant(
        name: name,
        email: email,
        share: share ?? this.share,
        paid: paid ?? this.paid,
        isOwner: isOwner,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'share': share,
        'paid': paid,
        'isOwner': isOwner,
      };

  factory Participant.fromMap(Map<String, dynamic> m) => Participant(
        name: m['name'] as String,
        email: m['email'] as String,
        share: (m['share'] as num).toInt(),
        paid: m['paid'] as bool,
        isOwner: m['isOwner'] as bool? ?? false,
      );
}

/// One bill = one ticket.
class Ticket {
  const Ticket({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.currency,
    required this.items,
    this.tax = 0,
    this.serviceCharge = 0,
    this.tip = 0,
    this.country = 'MY',
    this.taxType = 'SST',
    this.printedTotal,
    this.reconciliationDiscrepancy = 0,
    this.requiresReview = false,
    this.splitPolicy = 'proportional',
    required this.participants,
    required this.status,
    required this.source,
    required this.createdAt,
    this.fxRates,
  });

  final String id;
  final String ownerId;
  final String title;
  final String currency;
  final List<TicketItem> items;

  /// Tax amount (SST/GST/VAT) in minor units.
  final int tax;

  /// Service charge amount in minor units.
  final int serviceCharge;

  /// Tip / Rounding in minor units.
  final int tip;

  final String country; // "MY" or "SG"
  final String taxType; // "SST" or "GST"
  final int? printedTotal;
  final int reconciliationDiscrepancy;
  final bool requiresReview;
  final String splitPolicy; // "proportional" or "equal"

  final List<Participant> participants;
  final TicketStatus status;

  /// `manual` or `scan`.
  final String source;
  final DateTime createdAt;

  /// Exchange-rate snapshot (units per 1 USD) taken when the ticket was created.
  final Map<String, double>? fxRates;

  int get subtotal => items.fold(0, (sum, i) => sum + i.total);
  int get computedTotal => subtotal + tax + serviceCharge + tip;
  int get total => printedTotal ?? computedTotal;

  Ticket copyWith({
    List<Participant>? participants,
    TicketStatus? status,
    int? tax,
    int? serviceCharge,
    int? tip,
    int? printedTotal,
    int? reconciliationDiscrepancy,
    bool? requiresReview,
    String? splitPolicy,
  }) =>
      Ticket(
        id: id,
        ownerId: ownerId,
        title: title,
        currency: currency,
        items: items,
        tax: tax ?? this.tax,
        serviceCharge: serviceCharge ?? this.serviceCharge,
        tip: tip ?? this.tip,
        country: country,
        taxType: taxType,
        printedTotal: printedTotal ?? this.printedTotal,
        reconciliationDiscrepancy:
            reconciliationDiscrepancy ?? this.reconciliationDiscrepancy,
        requiresReview: requiresReview ?? this.requiresReview,
        splitPolicy: splitPolicy ?? this.splitPolicy,
        participants: participants ?? this.participants,
        status: status ?? this.status,
        source: source,
        createdAt: createdAt,
        fxRates: fxRates,
      );

  /// Calculates each participant's share deterministically.
  Ticket recalculated() {
    if (participants.isEmpty) return copyWith(status: TicketStatus.draft);

    final hasCustomAssignments = items.any(
      (i) => !i.isVoidOrComplimentary && i.assignedEmails.isNotEmpty,
    );

    List<int> totalShares;

    if (!hasCustomAssignments || splitPolicy == 'equal') {
      totalShares = Money.splitEqually(total, participants.length);
    } else {
      final itemSubtotals = List<int>.filled(participants.length, 0);

      for (final item in items) {
        if (item.isVoidOrComplimentary) continue;

        final assigned = item.assignedEmails.isEmpty
            ? participants
            : participants
                .where((p) => item.assignedEmails.contains(p.email.toLowerCase()))
                .toList();

        final effectiveAssigned = assigned.isEmpty ? participants : assigned;
        final shares = Money.splitEqually(item.total, effectiveAssigned.length);

        for (var i = 0; i < effectiveAssigned.length; i++) {
          final pEmail = effectiveAssigned[i].email.toLowerCase();
          final pIndex = participants.indexWhere((p) => p.email.toLowerCase() == pEmail);
          if (pIndex != -1) {
            itemSubtotals[pIndex] += shares[i];
          }
        }
      }

      final totalItemSubtotal = itemSubtotals.fold<int>(0, (a, b) => a + b);
      final totalExtra = tax + serviceCharge + tip;

      if (totalExtra != 0 && totalItemSubtotal > 0) {
        final extraShares = Money.allocate(totalExtra, itemSubtotals);
        totalShares = [
          for (var i = 0; i < participants.length; i++)
            itemSubtotals[i] + extraShares[i],
        ];
      } else {
        totalShares = itemSubtotals;
      }
    }

    final updated = [
      for (var i = 0; i < participants.length; i++)
        participants[i].copyWith(share: totalShares[i]),
    ];

    final discrepancy = (printedTotal != null) ? (printedTotal! - computedTotal) : 0;
    final needsReview = requiresReview || discrepancy != 0;

    final others = updated.where((p) => !p.isOwner).toList();
    final newStatus = others.isEmpty
        ? TicketStatus.draft
        : others.every((p) => p.paid)
            ? TicketStatus.settled
            : others.any((p) => p.paid)
                ? TicketStatus.partiallyPaid
                : TicketStatus.open;

    return copyWith(
      participants: updated,
      status: newStatus,
      reconciliationDiscrepancy: discrepancy,
      requiresReview: needsReview,
    );
  }

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'title': title,
        'currency': currency,
        'items': items.map((i) => i.toMap()).toList(),
        'tax': tax,
        'serviceCharge': serviceCharge,
        'tip': tip,
        'country': country,
        'taxType': taxType,
        'printedTotal': printedTotal,
        'reconciliationDiscrepancy': reconciliationDiscrepancy,
        'requiresReview': requiresReview,
        'splitPolicy': splitPolicy,
        'participants': participants.map((p) => p.toMap()).toList(),
        'memberEmails': participants.map((p) => p.email.toLowerCase()).toList(),
        'status': status.name,
        'source': source,
        'createdAt': Timestamp.fromDate(createdAt),
        'fxRates': fxRates,
      };

  factory Ticket.fromMap(String id, Map<String, dynamic> m) => Ticket(
        id: id,
        ownerId: m['ownerId'] as String,
        title: m['title'] as String,
        currency: m['currency'] as String,
        items: (m['items'] as List)
            .map((e) => TicketItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        tax: (m['tax'] as num? ?? 0).toInt(),
        serviceCharge: (m['serviceCharge'] as num? ?? 0).toInt(),
        tip: (m['tip'] as num? ?? 0).toInt(),
        country: m['country'] as String? ?? 'MY',
        taxType: m['taxType'] as String? ?? 'SST',
        printedTotal: (m['printedTotal'] as num?)?.toInt(),
        reconciliationDiscrepancy: (m['reconciliationDiscrepancy'] as num? ?? 0).toInt(),
        requiresReview: m['requiresReview'] as bool? ?? false,
        splitPolicy: m['splitPolicy'] as String? ?? 'proportional',
        participants: (m['participants'] as List)
            .map((e) => Participant.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        status: TicketStatus.values.byName(m['status'] as String),
        source: m['source'] as String,
        createdAt: (m['createdAt'] as Timestamp).toDate(),
        fxRates: (m['fxRates'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
}
