# Screen map

Fallback when grepping the screenshot's visible text fails. All paths are
relative to `inaagapay_flutter_v2/`.

## Midwife shell

`lib/screens/midwife/midwife_shell.dart` owns the header (`MainHeader`) and the
bottom navigation. The four tabs render inside it, so a tab file has no header
of its own — a header defect belongs to the shell or to
`lib/widgets/main_header.dart`, not to the tab.

| Tab | Header label | File |
| --- | --- | --- |
| 0 | HOME | `lib/screens/midwife/midwife_dashboard.dart` |
| 1 | MOTHERS | `lib/screens/midwife/midwife_mothers_screen.dart` |
| 2 | CHILDREN | `lib/screens/midwife/midwife_children_screen.dart` |
| 3 | SCHEDULES | `lib/screens/midwife/midwife_schedules_screen.dart` |

## Midwife screens by purpose

**Mothers / pregnancy**
- Add or edit a mother, all steps — `midwife_add_mother_screen.dart` (very large)
- Start a pregnancy — `start_pregnancy_screen.dart`
- Prenatal checkup form — `add_prenatal_checkup_screen.dart` (very large)
- Lab test entry — `add_lab_test_page.dart`
- Ultrasound entry — `add_ultrasound_page.dart`
- Ultrasound analysis — `ultrasound_analyzer_screen.dart` (very large)
- Lab test analysis — `lab_test_analyzer_screen.dart`
- Maternal TD doses — `maternal_td_screen.dart`
- Legacy list — `midwife_mother_list.dart`

**Children**
- Add child entry choice — `add_child_choice.dart`
- Pick the mother — `add_child_select_mother.dart`
- Child details step — `add_child_step3_child.dart`
- Birth details step — `add_child_step4_birth.dart`
- Child profile — `child_profile_page.dart`
- Growth records list — `child_growth_list_page.dart`
- Add growth record — `add_growth_step1.dart`
- Growth history — `growth_history_screen.dart`
- Immunization records list — `child_immunization_list_page.dart`
- Add immunization — `add_immunization_page.dart`, `add_immunization_choice.dart`
- Immunization OCR review — `immunization_ocr_review_page.dart`

**Operations**
- Calendar — `midwife_calendar.dart`
- Vaccination drive — `midwife_vaccination_drive_page.dart`
- SMS reminders — `midwife_sms_reminders_screen.dart`
- Notification center — `midwife_notification_center.dart`
- Records — `midwife_records.dart`
- Profile — `midwife_profile_page.dart`
- Help — `midwife_help_page.dart`
- Inventory — `lib/screens/midwife_inventory/midwife_inventory_page.dart` (very large)

## Shared widgets that appear on many screens

Fix these once instead of patching each screen — then check the other call
sites. All under `lib/widgets/`.

- Chrome: `main_header.dart`, `secondary_header.dart`,
  `midwife_bottom_navigation.dart`, `main_bottom_navigation.dart`,
  `page_title.dart`, `headline.dart`
- Cards: `midwife_statistics_card.dart`, `midwife_history_card.dart`,
  `hero_card.dart`, `chart_card.dart`, `comparison_card.dart`,
  `record_cards.dart`, `records_display_card.dart`, `growth_record_card.dart`,
  `growth_summary_card.dart`, `profile_*.dart`, `pregnancy_*.dart`,
  `trimester_card.dart`, `danger_signs_card.dart`, `ai_analytics_card.dart`
- Rows and boxes: `info_row.dart`, `overview_info.dart`, `small_info_box.dart`,
  `long_info_box.dart`, `status_indicator.dart`, `stock_indicators.dart`
- Inputs: `app_input_field.dart`, `app_dropdown_field.dart`, `aog_input.dart`,
  `otp_input_field.dart`, `calculation_dropdown.dart`, `search_bar.dart`,
  `branded_date_picker.dart`
- Buttons: `main_button.dart`, `secondary_button.dart`, `modal_button.dart`,
  `important_button.dart`, `tab_button.dart`
- Dialogs: `dialog_box.dart`, `confirmation_dialog_box.dart`,
  `app_snackbar.dart`
- Charts: `growth_line_chart.dart`, `widgets/analytics/`
- Baby book: `widgets/baby_book/`

## Locating by text — preferred method

```bash
grep -rn "<exact visible string>" inaagapay_flutter_v2/lib
```

For dynamic values, grep the nearest static label, the section heading, or a
distinctive icon (`Icons.pregnant_woman`, `Icons.vaccines`).

## Other roles

Same rules apply, different folders: `lib/screens/mother/`,
`lib/screens/admin/`, `lib/screens/auth/`, `lib/screens/shared/`.
