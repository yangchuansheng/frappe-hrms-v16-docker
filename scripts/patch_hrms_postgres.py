from pathlib import Path

PATCHES = {
    "apps/hrms/hrms/patches/post_install/move_payroll_setting_separately_from_hr_settings.py": {
        'doctype = "HR Settings"': "doctype = 'HR Settings'",
        '"encrypt_salary_slips_in_emails"': "'encrypt_salary_slips_in_emails'",
        '"email_salary_slip_to_employee"': "'email_salary_slip_to_employee'",
        '"daily_wages_fraction_for_half_day"': "'daily_wages_fraction_for_half_day'",
        '"disable_rounded_total"': "'disable_rounded_total'",
        '"include_holidays_in_total_working_days"': "'include_holidays_in_total_working_days'",
        '"max_working_hours_against_timesheet"': "'max_working_hours_against_timesheet'",
        '"payroll_based_on"': "'payroll_based_on'",
        '"password_policy"': "'password_policy'",
    },
    "apps/hrms/hrms/patches/post_install/update_employee_advance_status.py": {
        "& ((advance.return_amount) & (advance.paid_amount == advance.return_amount))": "& ((advance.return_amount > 0) & (advance.paid_amount == advance.return_amount))",
        "(advance.claimed_amount & advance.return_amount)": "((advance.claimed_amount > 0) & (advance.return_amount > 0))",
    },
    "apps/frappe/frappe/desk/doctype/number_card/number_card.py": {
        """res = frappe.get_list(
		doc.document_type, fields=fields, filters=filters, parent_doctype=doc.parent_document_type
	)""": """res = frappe.get_list(
		doc.document_type,
		fields=fields,
		filters=filters,
		parent_doctype=doc.parent_document_type,
		order_by="",
	)""",
    },
}


def main() -> None:
    changed_files = []
    missing_replacements = []

    for filename, replacements in PATCHES.items():
        path = Path(filename)
        if not path.exists():
            raise SystemExit(f"Patch target not found: {filename}")

        text = path.read_text()
        new_text = text
        for old, new in replacements.items():
            if old in new_text:
                new_text = new_text.replace(old, new)
            elif new not in new_text:
                missing_replacements.append(f"{filename}: {old!r}")

        if new_text != text:
            path.write_text(new_text)
            changed_files.append(filename)

    if missing_replacements:
        details = "\n".join(missing_replacements)
        raise SystemExit(f"PostgreSQL compatibility patch target changed:\n{details}")

    if changed_files:
        print("Patched Frappe/HRMS PostgreSQL compatibility:", ", ".join(changed_files))
    else:
        print("Frappe/HRMS PostgreSQL compatibility patches already applied")


if __name__ == "__main__":
    main()
