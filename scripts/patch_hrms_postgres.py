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
    "apps/erpnext/erpnext/accounts/report/asset_depreciations_and_balances/asset_depreciations_and_balances.py": {
        "IfNull(asset.disposal_date, 0) == 0": "asset.disposal_date.isnull()",
        "IfNull(asset.disposal_date, 0) != 0": "asset.disposal_date.notnull()",
    },
    "apps/erpnext/erpnext/controllers/trends.py": {
        """SUM(IF(t1.{trans_date} BETWEEN '{sd}' AND '{ed}', t2.stock_qty, NULL)),
					SUM(IF(t1.{trans_date} BETWEEN '{sd}' AND '{ed}', t2.base_net_amount, NULL)),""": """SUM(CASE WHEN t1.{trans_date} BETWEEN '{sd}' AND '{ed}' THEN t2.stock_qty ELSE NULL END),
					SUM(CASE WHEN t1.{trans_date} BETWEEN '{sd}' AND '{ed}' THEN t2.base_net_amount ELSE NULL END),""",
        'based_on_details["based_on_group_by"] = "t2.item_code"': 'based_on_details["based_on_group_by"] = "t2.item_code, t2.item_name"',
        'based_on_details["based_on_group_by"] = "t1.party_name" if trans == "Quotation" else "t1.customer"': """based_on_details["based_on_group_by"] = (
				"t1.party_name, t1.customer_name, t1.territory"
				if trans == "Quotation"
				else "t1.customer, t1.customer_name, t1.territory"
			)""",
        'based_on_details["based_on_group_by"] = "t1.supplier"': 'based_on_details["based_on_group_by"] = "t1.supplier, t1.supplier_name, t3.supplier_group"',
        """based_on_details["addl_tables_relational_cond"] = (
		based_on_details.get("addl_tables_relational_cond", "") + " and t1.company = t4.name"
	)""": """based_on_details["addl_tables_relational_cond"] = (
		based_on_details.get("addl_tables_relational_cond", "") + " and t1.company = t4.name"
	)
	based_on_details["based_on_group_by"] += ", t4.default_currency\"""",
        """and t1.docstatus = 1 and {} = {} and {} = {} {} {}
						\"\"\".format(""": """and t1.docstatus = 1 and {} = {} and {} = {} {} {}
								group by t4.default_currency, {}
						\"\"\".format(""",
        """conditions.get("addl_tables_relational_cond"),
						cond,
					),""": """conditions.get("addl_tables_relational_cond"),
						cond,
						sel_col,
					),""",
    },
    "apps/erpnext/erpnext/assets/doctype/location/location.py": {
        """return frappe.db.sql(
		f\"\"\"
		select
			name as value,
			is_group as expandable
		from
			`tabLocation` comp
		where
			ifnull(parent_location, \"\")={frappe.db.escape(parent)}
		\"\"\",
		as_dict=1,
	)""": """return frappe.db.sql(
		\"\"\"
		select
			name as value,
			is_group as expandable
		from
			`tabLocation` comp
		where
			coalesce(parent_location, '')=%s
		\"\"\",
		(parent,),
		as_dict=1,
	)""",
    },
    "apps/erpnext/erpnext/buying/report/purchase_order_analysis/purchase_order_analysis.py": {
        """.groupby(po_item.name)""": """.groupby(
				po.transaction_date,
				po_item.schedule_date,
				po_item.project,
				po.name,
				po.status,
				po.supplier,
				po_item.item_code,
				po_item.qty,
				po_item.received_qty,
				po_item.base_amount,
				po_item.billed_amt,
				po.conversion_rate,
				po.set_warehouse,
				po.company,
				po_item.name,
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
