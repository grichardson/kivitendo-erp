-- @tag: add_fkey_tax_id_to_acc_trans
-- @description: Setzt einen Fremdschlüssel zu der Tabellenspalte tax_id in der acc_trans
-- @depends: release_3_0_0

ALTER TABLE acc_trans ADD FOREIGN KEY (tax_id) REFERENCES tax(id);
