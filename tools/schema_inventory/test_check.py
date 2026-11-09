import copy
import unittest
from check import scan_text, validate


class InventoryCheckTest(unittest.TestCase):
    def test_collects_conditional_virtual_views_and_renames(self):
        result = scan_text('''CREATE TABLE IF NOT EXISTS items(id INTEGER);
CREATE VIRTUAL TABLE cache_fts USING fts5(name);
CREATE VIEW totals AS SELECT 1;
ALTER TABLE items RENAME TO old_items;''', 'lib/example.dart')
        self.assertEqual(set(result), {'items', 'cache_fts', 'totals', 'old_items'})
        self.assertEqual(result['cache_fts']['kind'], 'virtual_table')
        self.assertEqual(result['old_items']['sources'][0]['operation'], 'rename')
        self.assertEqual(result['totals']['sources'][0]['line'], 3)

    def test_dynamic_names_fail_closed(self):
        for statement in ['CREATE TABLE $table(id INTEGER)',
                          'CREATE TABLE IF NOT EXISTS $table(id INTEGER)',
                          'ALTER TABLE items RENAME TO $destination']:
            with self.assertRaises(ValueError):
                scan_text(statement, 'lib/dynamic.dart')

    def test_duplicate_declarations_keep_both_sources(self):
        result = scan_text('CREATE TABLE items(id);\nCREATE TABLE IF NOT EXISTS items(id);', 'lib/schema.dart')
        self.assertEqual(len(result), 1)
        self.assertEqual(len(result['items']['sources']), 2)

    def test_missing_or_stale_classifications_fail(self):
        objects = {'items': {'kind': 'table'}}
        with self.assertRaises(ValueError):
            validate(objects, {}, set())
        with self.assertRaises(ValueError):
            validate({}, self.registry(), {'items'})

    def registry(self):
        return {'items': {'classification': 'syncable', 'sync_allowed': True,
                          'lifecycle': 'schema', 'reason_ar': 'Reviewed fields'}}

    def test_allowlist_drift_and_sensitive_opt_in_fail(self):
        objects = {'items': {'kind': 'table'}}
        validate(objects, self.registry(), {'items'})
        with self.assertRaises(ValueError):
            validate(objects, self.registry(), set())
        registry = copy.deepcopy(self.registry())
        registry['items']['classification'] = 'sensitive'
        with self.assertRaises(ValueError):
            validate(objects, registry, {'items'})

    def test_views_cannot_be_sync_targets(self):
        with self.assertRaises(ValueError):
            validate({'items': {'kind': 'view'}}, self.registry(), {'items'})


if __name__ == '__main__':
    unittest.main()
