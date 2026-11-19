import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/links.dart';
import '../../widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final info = context.watch<Session>().info;
    return Scaffold(
      appBar: AppBar(title: Text('About ${info.orgName}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/images/logo.png', width: 96, height: 96),
            ),
          ),
          const SizedBox(height: 14),
          Text(info.orgName,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(info.tagline, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 20),
          if (info.about.isNotEmpty)
            CardBox(child: Text(info.about, style: const TextStyle(height: 1.55, fontSize: 15))),
          const SizedBox(height: 14),
          CardBox(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (info.phone.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.call_outlined, color: AppColors.primary),
                    title: Text(info.phone),
                    onTap: () => callPhone(info.phone),
                  ),
                if (info.email.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.mail_outline, color: AppColors.primary),
                    title: Text(info.email),
                    onTap: () => sendEmail(info.email),
                  ),
                if (info.address.isNotEmpty)
                  ListTile(leading: const Icon(Icons.place_outlined, color: AppColors.primary), title: Text(info.address)),
                if (info.hours.isNotEmpty)
                  ListTile(leading: const Icon(Icons.access_time, color: AppColors.primary), title: Text(info.hours)),
                if (info.website.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.public, color: AppColors.primary),
                    title: Text(info.website),
                    onTap: () => openLink(info.website),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (info.youtube.isNotEmpty)
                _SocialButton(icon: Icons.play_circle_outline, label: 'YouTube', url: info.youtube),
              if (info.instagram.isNotEmpty)
                _SocialButton(icon: Icons.photo_camera_outlined, label: 'Instagram', url: info.instagram),
              if (info.linkedin.isNotEmpty)
                _SocialButton(icon: Icons.work_outline, label: 'LinkedIn', url: info.linkedin),
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.icon, required this.label, required this.url});

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      onPressed: () => openLink(url),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
