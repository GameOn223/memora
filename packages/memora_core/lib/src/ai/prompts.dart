import '../model/understanding.dart';
import 'capabilities.dart';

/// Prompts and schemas shared by every vision adapter, so all providers are
/// asked the same question and return the same shape.
abstract final class VisionPrompts {
  /// System instructions for [VisionService.analyze].
  static String analyzeInstructions(VisionRequest request) {
    final taken = _isoDate(request.takenAt);
    return '''
You turn one image from the user's phone into structured data for a personal memory app. The user saved this image on purpose because it holds something they want to find later.

Return only JSON that matches the schema.

- summary: one specific sentence someone would use to find this image later. Name the company, product, place or person when visible. Do not start with "This image".
- category: one of ${suggestedCategories.join(', ')}. Use other only when nothing fits.
- visual_description: one or two sentences on what kind of screen, document or scene this is.
- extracted_text: the important visible text in reading order, with line breaks. Skip status bar clutter such as the clock, battery and signal icons. Keep it under 2000 characters.
- keywords: 3 to 12 lowercase search terms, including words a person might type that are not visible, such as "electricity" for a power bill.
- entities: companies, organizations, people, locations, products and brands. Use those words as the type.
- dates: every meaningful date as YYYY-MM-DD with a snake_case type such as due_date, transaction_date, event_date, booking_date, departure_date or expiry_date. The image was taken on $taken. Use that to fill in a missing year.
- amounts: money values with a type (total, subtotal, price, tax, discount, balance, fee), the number without separators, and an ISO 4217 currency. Assume ${request.defaultCurrency} when only a symbol like Rs or ₹ appears.
- attributes: other identifiers such as invoice_number, order_number, tracking_number, booking_reference, account_number, phone, email, url, address, product_name and model_number. Mask account and card numbers to their last four digits, for example "•••• 4471".
- confidence: a number from 0 to 1 for how sure you are the extraction is correct.

Only report values you can see in the image. Leave a list empty rather than guessing.''';
  }

  /// User turn text that accompanies the image.
  static const analyzeUserText = 'Extract the memory data for this image.';

  /// JSON schema for [MemoryUnderstanding]. Kept to the subset of JSON
  /// schema every provider adapter can send as it is.
  static const Map<String, Object?> understandingSchema = {
    'type': 'object',
    'properties': {
      'summary': {'type': 'string'},
      'category': {'type': 'string'},
      'visual_description': {'type': 'string'},
      'extracted_text': {'type': 'string'},
      'keywords': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'entities': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'type': {'type': 'string'},
            'value': {'type': 'string'},
          },
          'required': ['type', 'value'],
        },
      },
      'dates': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'type': {'type': 'string'},
            'value': {'type': 'string'},
          },
          'required': ['type', 'value'],
        },
      },
      'amounts': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'type': {'type': 'string'},
            'value': {'type': 'number'},
            'currency': {'type': 'string'},
          },
          'required': ['type', 'value', 'currency'],
        },
      },
      'attributes': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'type': {'type': 'string'},
            'value': {'type': 'string'},
          },
          'required': ['type', 'value'],
        },
      },
      'confidence': {'type': 'number'},
    },
    'required': [
      'summary',
      'category',
      'visual_description',
      'extracted_text',
      'keywords',
      'entities',
      'dates',
      'amounts',
      'attributes',
      'confidence',
    ],
  };

  /// Instructions for [VisionService.verify].
  static String verifyInstructions(VerificationRequest request) =>
      '''
Check one fact against the image.

Field: ${request.attributeType}
Expected value: ${request.expectedValue}

Return only JSON. Set confirmed to true when the image clearly shows that value for that field. Set observed_value to the value exactly as the image shows it, or null if the field is not visible.''';

  static const Map<String, Object?> verificationSchema = {
    'type': 'object',
    'properties': {
      'confirmed': {'type': 'boolean'},
      'observed_value': {
        'type': ['string', 'null'],
      },
    },
    'required': ['confirmed', 'observed_value'],
  };

  static String _isoDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
