/// The Terms and Conditions of Use a mother agrees to before an account is
/// created.
///
/// The text lives here rather than inside the dialog for two reasons. The
/// research team edits wording between evaluation runs, and a paragraph buried
/// in a widget tree is the kind of thing that gets reflowed by accident during
/// a layout fix. Keeping it as data also means the same wording can be shown
/// somewhere else later — a Settings entry, a midwife account flow — without
/// anyone retyping it and quietly producing a second version of the terms.
///
/// Nothing in here is clinical guidance. Section 3 states the opposite: the
/// prototype does not diagnose, and its emergency sentence is carried in
/// [TermsSection.callout] so the dialog can lift it out of the legal prose
/// instead of letting it be skimmed past.
library;

/// The date the current wording takes effect, e.g. `'12 September 2026'`.
///
/// Left blank on purpose. Fill it in before the evaluation run — the dialog
/// header omits the line while this is empty, so an unfilled date shows as
/// nothing rather than as a bracketed placeholder in front of a panel.
const String termsEffectiveDate = '';

/// One numbered clause of the terms.
class TermsSection {
  const TermsSection({
    required this.number,
    required this.title,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
    this.closing,
    this.callout,
  });

  /// Shown in the badge beside the title, e.g. `'3'`.
  final String number;

  final String title;

  /// Body prose, in order, rendered as separate paragraphs.
  final List<String> paragraphs;

  /// Rendered as a bulleted list under [paragraphs]. Empty for most sections.
  final List<String> bullets;

  /// Prose that follows the bullets, e.g. the prohibitions in section 5.
  final String? closing;

  /// A sentence that must not be skimmed — rendered as a tinted callout.
  final String? callout;
}

/// A person or office a user can reach about the study.
class TermsContact {
  const TermsContact({required this.role, required this.entries});

  final String role;

  /// One line per person, already formatted for display.
  final List<String> entries;
}

/// The opening statement, shown above the numbered sections.
const String termsIntroduction =
    'InaAgapay is an academic research prototype developed to support the '
    'documentation, monitoring, and communication of maternal and child health '
    'information. By accessing the system, the user agrees to comply with the '
    'following conditions.';

const List<TermsSection> termsSections = <TermsSection>[
  TermsSection(
    number: '1',
    title: 'Authorized Use',
    paragraphs: <String>[
      'Access is limited to authorized research participants, evaluators, and '
          'designated personnel. Users may access only the functions and '
          'information permitted for their assigned role.',
      'Users must not share their passwords, allow another person to use their '
          'account, or attempt to access another user\'s information.',
    ],
  ),
  TermsSection(
    number: '2',
    title: 'Use of Simulated Data',
    paragraphs: <String>[
      'During the study, InaAgapay must be used only with fictional or '
          'simulated maternal and child health information. Users must not '
          'enter, upload, photograph, or transmit actual patient health '
          'records or personally identifiable medical information.',
      'The system is being evaluated as a research prototype and is not yet '
          'authorized for routine clinical operation.',
    ],
  ),
  TermsSection(
    number: '3',
    title: 'Non-Diagnostic Purpose',
    paragraphs: <String>[
      'InaAgapay does not provide medical diagnoses, prescribe treatment, or '
          'replace consultation with a qualified healthcare professional.',
      'The system may compare recorded information with established monitoring '
          'standards and display recommendations or flags for professional '
          'review. These results must not be treated as final clinical '
          'conclusions or medical orders.',
    ],
    callout:
        'InaAgapay must not be used during a medical emergency. Contact an '
        'appropriate healthcare facility or emergency service immediately when '
        'urgent medical attention is needed.',
  ),
  TermsSection(
    number: '4',
    title: 'AI-Assisted Functions',
    paragraphs: <String>[
      'AI-assisted functions may extract information from uploaded documents '
          'or present rule-based monitoring results in plain language. '
          'Artificial intelligence does not independently determine the '
          'system\'s monitoring classifications.',
      'Information extracted from documents must be reviewed and corrected, '
          'when necessary, by the recording midwife before it is saved. '
          'AI-assisted explanations are non-diagnostic and remain subject to '
          'healthcare-professional review.',
    ],
  ),
  TermsSection(
    number: '5',
    title: 'User Responsibilities',
    paragraphs: <String>['Users agree to:'],
    bullets: <String>[
      'provide accurate information when completing research and evaluation '
          'activities;',
      'review information before confirming or saving it;',
      'protect account credentials and report suspected unauthorized access;',
      'use the system only for its intended academic and evaluation purposes; '
          'and',
      'maintain the confidentiality of information displayed during the '
          'evaluation.',
    ],
    closing:
        'Users must not attempt to bypass security controls, modify records '
        'without authorization, interfere with system operation, upload '
        'harmful content, or use screenshots and exported information for '
        'unauthorized purposes.',
  ),
  TermsSection(
    number: '6',
    title: 'Notifications and Recommendations',
    paragraphs: <String>[
      'SMS, email, and push notifications are intended to provide general '
          'reminders or inform users that a recommendation is available. They '
          'do not constitute medical advice or confirmation that a healthcare '
          'service has been missed.',
      'Notification delivery may be affected by incorrect contact details, '
          'network availability, device settings, or third-party service '
          'limitations.',
    ],
  ),
  TermsSection(
    number: '7',
    title: 'System Availability',
    paragraphs: <String>[
      'The research team does not guarantee uninterrupted access to the '
          'prototype. Functions may temporarily become unavailable because of '
          'internet connectivity, system maintenance, service limitations, or '
          'third-party provider interruptions.',
      'The unavailability of an AI-assisted function will not change the '
          'requirement for healthcare-professional assessment.',
    ],
  ),
  TermsSection(
    number: '8',
    title: 'Privacy and Confidentiality',
    paragraphs: <String>[
      'The collection and processing of personal information related to '
          'research participation will be governed by the InaAgapay Privacy '
          'Notice and Research Informed Consent Form.',
      'The system will apply role-based access and reasonable safeguards to '
          'protect information. However, users are also responsible for '
          'preventing unauthorized persons from viewing their accounts, '
          'devices, notifications, or exported records.',
    ],
  ),
  TermsSection(
    number: '9',
    title: 'Account Suspension and End of the Study',
    paragraphs: <String>[
      'Access may be restricted or suspended when an account is used without '
          'authorization, compromises system security, violates these terms, '
          'or is no longer required for the study.',
      'At the end of the research period, prototype accounts and simulated '
          'system data will be handled according to the retention and disposal '
          'periods stated in the Privacy Notice and approved research '
          'protocol.',
    ],
  ),
  TermsSection(
    number: '10',
    title: 'Changes to These Terms',
    paragraphs: <String>[
      'The research team may revise these terms when necessary to reflect '
          'changes in the prototype or study procedures. Users will be '
          'informed of material changes before continuing participation. '
          'Changes affecting research participation or personal-data '
          'processing may require renewed consent.',
    ],
  ),
  TermsSection(
    number: '11',
    title: 'Contact Information',
    paragraphs: <String>[
      'Questions, privacy concerns, or suspected unauthorized access may be '
          'reported to:',
    ],
  ),
];

/// Rendered as cards under section 11.
const List<TermsContact> termsContacts = <TermsContact>[
  TermsContact(
    role: 'Research Team',
    entries: <String>[
      'Jass Myne Carpio — 09235316346',
      'Errol Kelvin Tolentino — 09457738468',
      'Brent Lawrence Bernardo — 09936271374',
    ],
  ),
  TermsContact(
    role: 'Research Adviser',
    entries: <String>['Eliza Pascual — empascual@nu-baliwag.edu.ph'],
  ),
  TermsContact(
    role: 'Institution / Data Protection Officer',
    entries: <String>['National University Baliwag'],
  ),
];

/// The sentence the checkbox and the "I Agree" button both stand for.
const String termsAcknowledgment =
    'By selecting "I Agree," I confirm that I have read and understood these '
    'Terms and Conditions of Use. I understand that InaAgapay is a research '
    'prototype, must use only simulated health information during the study, '
    'and does not provide medical diagnoses or replace healthcare '
    'professionals.';
