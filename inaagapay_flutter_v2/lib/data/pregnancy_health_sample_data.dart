import '../models/pregnancy_health_record.dart';

final List<PregnancyHealthRecord> pregnancyHealthSampleRecords = [
  PregnancyHealthRecord(
    id: 'sample-tetanus-record',
    type: PregnancyRecordType.vaccination,
    name: 'Tetanus-containing Vaccine',
    recordDate: DateTime(2026, 6, 12),
    providerName: 'Midwife',
    healthFacility: 'Sample Health Center',
    instructions: 'Follow the schedule recorded by your healthcare provider.',
    notes: 'Sample record for this Baby Book mockup.',
    status: PregnancyRecordStatus.completed,
    nextScheduledDate: DateTime(2026, 7, 28),
    isSample: true,
  ),
  PregnancyHealthRecord(
    id: 'sample-iron-folic-record',
    type: PregnancyRecordType.supplement,
    name: 'Iron and Folic Acid',
    recordDate: DateTime(2026, 6, 12),
    dosage: 'As prescribed',
    frequency: 'As prescribed',
    startDate: DateTime(2026, 6, 12),
    providerName: 'Healthcare Provider',
    healthFacility: 'Sample Health Center',
    instructions: 'Take only according to the provider-recorded instructions.',
    notes: 'Sample record—not an independent dosage recommendation.',
    status: PregnancyRecordStatus.active,
    isSample: true,
  ),
];
