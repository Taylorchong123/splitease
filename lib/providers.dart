import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/ticket_repository.dart';
import 'models/ticket.dart';
import 'services/currency_service.dart';

final authUserProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final ticketRepositoryProvider = Provider<TicketRepository>(
  (ref) => TicketRepository(FirebaseFirestore.instance),
);

final currencyServiceProvider = Provider<CurrencyService>((ref) => CurrencyService());

/// The currency the user wants to see converted totals in.
final preferredCurrencyProvider = StateProvider<String>((ref) => 'USD');

final ticketsProvider = StreamProvider<List<Ticket>>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .watch(ticketRepositoryProvider)
      .watchFor(uid: user.uid, email: user.email ?? '');
});

final ticketProvider = StreamProvider.family<Ticket?, String>((ref, id) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(ticketRepositoryProvider).watchOne(id);
});
