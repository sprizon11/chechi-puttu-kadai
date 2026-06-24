import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Primary Firestore database in **asia-south1** (Console name: `default`).
///
/// The project also has `(default)` in nam5, which errors in Firebase Console.
/// All app reads/writes must use this database.
const String kChechiFirestoreDatabaseId = 'default';

FirebaseFirestore get chechiFirestore => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: kChechiFirestoreDatabaseId,
    );
