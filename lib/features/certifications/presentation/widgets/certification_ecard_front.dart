import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/features/certifications/domain/entities/certification.dart';
import 'package:submersion/features/certifications/presentation/widgets/certification_card_photo.dart';

/// The front face of the certification card.
///
/// Shows the uploaded front photo when the diver captured one, otherwise a
/// generated card in the issuing agency's colours.
class CertificationEcardFront extends StatelessWidget {
  /// The certification to display.
  final Certification certification;

  /// The name of the diver holding this certification.
  final String diverName;

  const CertificationEcardFront({
    super.key,
    required this.certification,
    required this.diverName,
  });

  @override
  Widget build(BuildContext context) {
    final photo = certification.photoFront;
    if (photo != null) {
      return CertificationCardPhoto(
        bytes: photo,
        badge: _buildStatusBadge(context),
        infoLines: _buildInfoLines(),
      );
    }
    return _buildGeneratedFront(context);
  }

  /// Lines repeated over a photographed card.
  ///
  /// The scrim covers the part of a physical card that prints the holder's name
  /// and number, so repeating them here loses nothing and keeps the text legible
  /// when the photo is dim or blurry.
  List<String> _buildInfoLines() {
    final cardNumber = certification.cardNumber;

    final headline = [
      certification.agency.displayName,
      certification.name,
    ].where((value) => value.isNotEmpty).join('  -  ');

    final detail = [
      diverName.toUpperCase(),
      if (cardNumber != null && cardNumber.isNotEmpty) cardNumber,
    ].where((value) => value.isNotEmpty).join('  -  ');

    return [if (headline.isNotEmpty) headline, if (detail.isNotEmpty) detail];
  }

  Widget _buildGeneratedFront(BuildContext context) {
    final agency = certification.agency;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          CertificationCardPhoto.borderRadius,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [agency.primaryColor, agency.secondaryColor],
        ),
        boxShadow: [
          BoxShadow(
            color: agency.primaryColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative wave pattern
          Positioned.fill(
            child: CustomPaint(
              painter: _WavePatternPainter(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          // Card content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: agency name and status badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        agency.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    _buildStatusBadge(context) ?? const SizedBox.shrink(),
                  ],
                ),
                const Spacer(),
                // Center: certification name
                Text(
                  certification.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // Level display if present
                if (certification.level != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    certification.level!.displayName,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                const Spacer(),
                // Bottom row: diver info and issue date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            diverName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (certification.cardNumber != null &&
                              certification.cardNumber!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              certification.cardNumber!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                                letterSpacing: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (certification.issueDate != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.certifications_ecard_label_issued,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat(
                              'MM/yy',
                            ).format(certification.issueDate!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The expiry status chip, or null when the certification is current.
  ///
  /// Returns null rather than an empty box so the photo branch can decide
  /// whether to position anything at all.
  Widget? _buildStatusBadge(BuildContext context) {
    if (certification.isExpired) {
      return _badge(
        context.l10n.certifications_ecard_statusBadge_expired,
        Colors.red,
      );
    }

    if (certification.expiresWithin(90)) {
      return _badge(
        context.l10n.certifications_ecard_statusBadge_expiring,
        Colors.orange,
      );
    }

    return null;
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Custom painter for decorative wave pattern on the card.
class _WavePatternPainter extends CustomPainter {
  final Color color;

  _WavePatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw decorative circles at various positions
    final circles = [
      (Offset(size.width * 0.85, size.height * 0.2), size.width * 0.25),
      (Offset(size.width * 0.95, size.height * 0.6), size.width * 0.18),
      (Offset(size.width * 0.1, size.height * 0.9), size.width * 0.15),
      (Offset(size.width * 0.75, size.height * 0.85), size.width * 0.12),
    ];

    for (final (offset, radius) in circles) {
      canvas.drawCircle(offset, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePatternPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
