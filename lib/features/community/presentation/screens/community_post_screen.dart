import 'package:flutter/material.dart';

class CommunityPostScreen extends StatelessWidget {
  const CommunityPostScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Post $postId')),
    );
  }
}
