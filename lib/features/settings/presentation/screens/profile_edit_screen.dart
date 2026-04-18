// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';

// import '../../../../core/constants/theme_constants.dart';

// class ProfileEditScreen extends ConsumerWidget {
//   const ProfileEditScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return Scaffold(
//       backgroundColor: ThemeConstants.background,
//       appBar: AppBar(title: const Text('Edit Profile')),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(24),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             TextFormField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Name', prefixIcon: Icon(Icons.person_outline_rounded, color: ThemeConstants.textTertiary, size: 20))),
//             const SizedBox(height: 12),
//             TextFormField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.email_outlined, color: ThemeConstants.textTertiary, size: 20)), keyboardType: TextInputType.emailAddress),
//             const SizedBox(height: 12),
//             TextFormField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, color: ThemeConstants.textTertiary, size: 20)), keyboardType: TextInputType.phone),
//             const SizedBox(height: 24),
//             SizedBox(height: 48, child: ElevatedButton(onPressed: () {}, child: const Text('Save Changes'))),
//           ],
//         ),
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
// import '../../data/auth_remote_source.dart'; // 👈 ADD THIS
import '../../../auth/data/auth_remote_source.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {

  // ✅ STEP 1: Controllers
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final countryController = TextEditingController();
  final stateController = TextEditingController();
  final dobController = TextEditingController();
 final passwordController = TextEditingController();
  // ✅ STEP 2: Load data
  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  // void loadProfile() async {
  //   final user = await ref.read(authRemoteSourceProvider).getProfile();

  //   nameController.text = user.name ?? '';
  //   emailController.text = user.email ?? '';
  //   phoneController.text = user.phone ?? '';
  //   countryController.text = user.country ?? '';
  //   stateController.text = user.state ?? '';
  //   dobController.text = user.dob ?? '';
  // }
  void loadProfile() async {
  final user = await ref.read(authRemoteSourceProvider).getProfile();

  nameController.text =
      '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim();

  emailController.text = user.email ?? '';
  phoneController.text = user.phone ?? '';
  countryController.text = user.country ?? '';
  stateController.text = user.state ?? '';
  dobController.text = user.dob ?? '';
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ✅ Name
            TextFormField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Name',
                prefixIcon: Icon(Icons.person_outline_rounded, color: ThemeConstants.textTertiary, size: 20),
              ),
            ),
            const SizedBox(height: 12),

            // ✅ Email
            TextFormField(
              controller: emailController,
              readOnly: true, // Make email read-only
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, color: ThemeConstants.textTertiary, size: 20),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),

            // ✅ Phone
            TextFormField(
              controller: phoneController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined, color: ThemeConstants.textTertiary, size: 20),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),

            // ✅ Country
            TextFormField(
              controller: countryController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Country',
              ),
            ),
            const SizedBox(height: 12),

            // ✅ State
            TextFormField(
              controller: stateController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'State',
              ),
            ),
            const SizedBox(height: 12),

            // ✅ DOB
          TextFormField(
  controller: dobController,
  readOnly: true,
  style: const TextStyle(color: Colors.white),
  decoration: const InputDecoration(
    hintText: 'Date of Birth',
    prefixIcon: Icon(Icons.calendar_today, color: ThemeConstants.textTertiary, size: 20),
  ),
  onTap: () async {
    DateTime initialDate;

    // ✅ 1. Try to parse existing backend date
    try {
      initialDate = DateTime.parse(dobController.text);
    } catch (e) {
      initialDate = DateTime(2000); // fallback default
    }

    final pickedDate = await showDatePicker(
      context: context,

      // ✅ Start from existing DOB
      initialDate: initialDate,

      // ❌ No future dates allowed (today excluded)
      lastDate: DateTime.now().subtract(const Duration(days: 1)),

      // optional minimum age range
      firstDate: DateTime(1900),
    );

    if (pickedDate != null) {
      dobController.text =
          "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
    }
  },
),

            const SizedBox(height: 24),
            // psw 
    //         const Text('Password'),
    // TextFormField(
    //   controller: passwordController,
    //   obscureText: true,
    // ),

    const SizedBox(height: 24),
            // ✅ SAVE BUTTON
            SizedBox(
              height: 48,
              child: ElevatedButton(
// onPressed: () async {
//   try {
//     final parts = nameController.text.trim().split(' ');

//     final firstName = parts.isNotEmpty ? parts[0] : '';
//     final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

//     final response = await ref.read(authRemoteSourceProvider).updateProfile({
//       'firstName': firstName,
//       'lastName': lastName,
//       'email': emailController.text,
//       'phone': phoneController.text,
//       'country': countryController.text,
//       'state': stateController.text,
//       'dob': dobController.text,
//     });

//     print(response); // 🔥 DEBUG

//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Profile Updated')),
//     );
//   } catch (e) {
//     print(e); // 🔥 IMPORTANT
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Error: $e')),
//     );
//   }
// },
onPressed: () async {
  try {
    final parts = nameController.text.trim().split(' ');

    final firstName = parts.isNotEmpty ? parts[0] : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final data = {
      "firstName": firstName,
      "lastName": lastName,
      "phone": phoneController.text,
      "country": countryController.text,
      "state": stateController.text,
      "dateOfBirth": dobController.text,
    };

    print("SENDING DATA: $data"); // 🔥 DEBUG

    await ref.read(authRemoteSourceProvider).updateProfile(data);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile Updated")),
    );

  } catch (e) {
    print("SAVE ERROR: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error: $e")),
    );
  }
},
                 child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}