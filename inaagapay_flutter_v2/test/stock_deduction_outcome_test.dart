import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/stock_deduction_outcome.dart';

/// The payloads here are the ones the RPCs actually return, transcribed from
/// database/migrations/. If one of those jsonb_build_object calls changes shape,
/// these tests are where it should be noticed.
void main() {
  group('child immunisation — deduct_immunization_stock', () {
    test('dose drawn from an open vial', () {
      final o = StockDeductionOutcome.fromImmunization({
        'success': true,
        'mode': 'open_vial_dose',
        'batch_number': 'BCG-2026A',
        'doses_left_in_vial': 7,
        'doses_per_unit': 20,
      });
      expect(o.level, StockOutcomeLevel.deducted);
      expect(o.isProblem, isFalse);
      expect(o.lines.join(' '), contains('Batch #BCG-2026A'));
      expect(o.lines.join(' '), contains('7 doses'));
    });

    test('a fresh seal is broken', () {
      final o = StockDeductionOutcome.fromImmunization({
        'success': true,
        'mode': 'new_vial_opened',
        'batch_number': 'TD-99201',
        'doses_left_in_vial': 9,
        'doses_per_unit': 10,
      });
      expect(o.level, StockOutcomeLevel.deducted);
      expect(o.lines.join(' '), contains('10-dose'));
      expect(o.advice, isNotNull, reason: 'open doses are on a clock');
    });

    test('single-dose unit', () {
      final o = StockDeductionOutcome.fromImmunization({
        'success': true,
        'mode': 'single_dose',
        'batch_number': 'PENTA-1',
        'doses_left_in_vial': 0,
      });
      expect(o.level, StockOutcomeLevel.deducted);
      expect(o.lines.single, contains('Batch #PENTA-1'));
    });

    test('retry after a network hiccup does not claim a second deduction', () {
      final o = StockDeductionOutcome.fromImmunization(
          {'success': true, 'mode': 'already_deducted'});
      expect(o.level, StockOutcomeLevel.deducted);
      expect(o.lines.single, contains('already'));
    });

    test('out of stock is reported as a problem, not a success', () {
      final o = StockDeductionOutcome.fromImmunization({
        'success': false,
        'error': 'Out of stock: no usable BCG vial at this facility',
      });
      expect(o.level, StockOutcomeLevel.failed);
      expect(o.isProblem, isTrue);
      expect(o.lines.single, contains('Out of stock'));
      expect(o.advice, isNotNull);
    });

    test('an unreadable reply is never reported as a clean deduction', () {
      final o = StockDeductionOutcome.fromImmunization(null);
      expect(o.level, StockOutcomeLevel.notDeducted);
      expect(o.isProblem, isTrue);
    });

    test('given elsewhere draws from no shelf at all', () {
      final o = StockDeductionOutcome.fromImmunization(
          {'success': true, 'mode': 'single_dose'},
          givenElsewhere: true);
      expect(o.level, StockOutcomeLevel.notApplicable);
      expect(o.isProblem, isFalse);
    });
  });

  group('maternal Td — administer_maternal_td_dose', () {
    test('no_deduction is a warning, not a green success', () {
      // The regression this whole file exists for: the RPC answers
      // success:true with mode 'no_deduction' when it finds no batch, and the
      // screen used to show a plain success dialog.
      final o = StockDeductionOutcome.fromMaternalTd(
        {'success': true, 'mode': 'no_deduction', 'record_id': 12},
        doseKey: 'Td2',
      );
      expect(o.level, StockOutcomeLevel.notDeducted);
      expect(o.isProblem, isTrue);
      expect(o.headline.toLowerCase(), contains('did not move'));
    });

    test('dose from the open vial names the dose', () {
      final o = StockDeductionOutcome.fromMaternalTd({
        'success': true,
        'mode': 'open_vial_dose',
        'batch_number': 'TD-7',
        'doses_left_in_vial': 4,
      }, doseKey: 'Td3');
      expect(o.level, StockOutcomeLevel.deducted);
      expect(o.lines.first, contains('Td3'));
    });
  });

  group('prenatal encounter — deduct_prenatal_encounter_inventory', () {
    test('supplements and a Td dose both deducted', () {
      final o = StockDeductionOutcome.fromPrenatalEncounter({
        'success': true,
        'deductions': [
          {
            'item_type': 'supplement',
            'medication': 'Ferrous + FA',
            'quantity': 30,
            'requested': 30,
          },
          {
            'item_type': 'vaccine',
            'dose': 'Td2',
            'mode': 'open_vial_dose',
            'doses_remaining_in_vial': 6,
          },
        ],
        'warnings': [],
      });
      expect(o.level, StockOutcomeLevel.deducted);
      expect(o.lines, hasLength(2));
      expect(o.lines[0], contains('30 tablets'));
      expect(o.lines[1], contains('6 doses'));
    });

    test('a short supplement dispense is surfaced, not hidden', () {
      final o = StockDeductionOutcome.fromPrenatalEncounter({
        'success': true,
        'deductions': [
          {
            'item_type': 'supplement',
            'medication': 'Calcium',
            'quantity': 20,
            'requested': 30,
            'note': 'Only 20 of 30 were in stock',
          },
        ],
        'warnings': ['Calcium: 10 of 30 could not be deducted — stock ran out'],
      });
      expect(o.level, StockOutcomeLevel.partial);
      expect(o.isProblem, isTrue);
      expect(o.lines.any((l) => l.contains('only 20')), isTrue);
      expect(o.lines.any((l) => l.contains('could not be deducted')), isTrue,
          reason: 'the warnings array used to be dropped on the floor');
      expect(o.advice, isNotNull);
    });

    test('nothing in stock at all', () {
      final o = StockDeductionOutcome.fromPrenatalEncounter({
        'success': true,
        'deductions': [],
        'warnings': ['No Ferrous + FA in stock at this health center (30 requested)'],
      });
      expect(o.level, StockOutcomeLevel.notDeducted);
      expect(o.isProblem, isTrue);
    });

    test('a thrown RPC is reported as a failure', () {
      final o = StockDeductionOutcome.fromPrenatalEncounter({
        'success': false,
        'error': 'insert or update on table violates foreign key constraint',
      });
      expect(o.level, StockOutcomeLevel.failed);
      expect(o.isProblem, isTrue);
    });

    test('no health center assigned', () {
      final o = StockDeductionOutcome.fromPrenatalEncounter(null,
          facilityKnown: false);
      expect(o.level, StockOutcomeLevel.notDeducted);
      expect(o.lines.single, contains('not assigned'));
    });

    test('nothing dispensed says nothing about stock', () {
      final o = StockDeductionOutcome.fromPrenatalEncounter(
          {'success': true, 'deductions': [], 'warnings': []});
      expect(o.level, StockOutcomeLevel.notApplicable);
      expect(o.isProblem, isFalse);
      expect(o.lines, isEmpty);
    });

    test('pre-20260823 databases still spell the mode the old way', () {
      final o = StockDeductionOutcome.fromPrenatalEncounter({
        'success': true,
        'deductions': [
          {
            'item_type': 'vaccine',
            'dose': 'Td1',
            'mode': 'new_sealed_vial_opened',
            'doses_remaining_in_vial': 9,
          },
        ],
        'warnings': [],
      });
      expect(o.lines.single, contains('new vial opened'));
    });
  });

  group('body formatting', () {
    test('facts become bullets and advice follows them', () {
      final o = StockDeductionOutcome.fromImmunization({
        'success': false,
        'error': 'Out of stock',
      });
      expect(o.body, startsWith('• Out of stock'));
      expect(o.body, contains(o.advice!));
    });
  });
}
