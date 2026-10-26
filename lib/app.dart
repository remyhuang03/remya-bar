import 'package:material_ui/material_ui.dart';

class RemyaBarApp extends StatelessWidget {
  const RemyaBarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Remy'a Bar",
      debugShowCheckedModeBanner: false,
      theme: .new(
        useMaterial3: true,
        colorScheme: .fromSeed(
          seedColor: Colors.indigo,
          dynamicSchemeVariant: .expressive,
        ),
      ),
      home: const Scaffold(body: Center(child: Text('Hello, world!'))),
    );
  }
}
