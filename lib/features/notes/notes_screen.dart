import 'package:flutter/material.dart';

/// Distraction-free notes space: quick capture that mixes text, images,
/// and pen input in a single note. Placeholder until the editor and local
/// storage are built.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'No notes yet.\nTap + to capture your first one.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }
}
