-- Row Level Security + save_receipt tests. Each [n] line says what to expect.
\set ON_ERROR_STOP 0
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into people (id, name) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Amal'), ('aaaaaaaa-0000-0000-0000-000000000002', 'Bimal');
\echo [1 expect dup error]
insert into people (name) values ('amal');
\echo [2 save valid receipt]
select save_receipt('{"id":"bbbbbbbb-0000-0000-0000-000000000001","store_name":"KEELLS","receipt_date":"2026-11-01","total_cents":100,"image_path":null,"items":[{"id":"cccccccc-0000-0000-0000-000000000001","position":0,"name":"MILK","amount_cents":100,"category_id":"dairy","split_method":"equal","assignments":[{"person_id":"aaaaaaaa-0000-0000-0000-000000000001","position":0,"share":null,"allocated_cents":50},{"person_id":"aaaaaaaa-0000-0000-0000-000000000002","position":1,"share":null,"allocated_cents":50}]}]}');
\echo [3 expect sum error, then unchanged KEELLS 1 2]
select save_receipt('{"id":"bbbbbbbb-0000-0000-0000-000000000001","store_name":"CHANGED","receipt_date":"2026-11-01","total_cents":100,"items":[{"id":"cccccccc-0000-0000-0000-000000000002","position":0,"name":"MILK","amount_cents":100,"category_id":"dairy","split_method":"equal","assignments":[{"person_id":"aaaaaaaa-0000-0000-0000-000000000001","position":0,"allocated_cents":40}]}]}');
select store_name, (select count(*) from items) items, (select count(*) from assignments) asg from receipts;
\echo [4 expect restrict error]
delete from people where name = 'Amal';
\echo [5 re-save replaces items: KEELLS 2 BREAD]
select save_receipt('{"id":"bbbbbbbb-0000-0000-0000-000000000001","store_name":"KEELLS 2","receipt_date":"2026-11-02","total_cents":300,"items":[{"id":"cccccccc-0000-0000-0000-000000000003","position":0,"name":"BREAD","amount_cents":300,"category_id":"bakery","split_method":"exact","assignments":[{"person_id":"aaaaaaaa-0000-0000-0000-000000000002","position":0,"share":300,"allocated_cents":300}]}]}');
select store_name, (select string_agg(name, ',') from items) from receipts;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
\echo [6 B sees 0 0 0 0]
select (select count(*) from people), (select count(*) from receipts), (select count(*) from items), (select count(*) from assignments);
\echo [7 B: expect UPDATE 0 / DELETE 0]
update receipts set store_name = 'HACK';
delete from people;
\echo [8 B overwrites A receipt via save_receipt: expect error]
select save_receipt('{"id":"bbbbbbbb-0000-0000-0000-000000000001","store_name":"HACK","receipt_date":"2026-11-02","total_cents":0,"items":[]}');
\echo [9 B inserts item into A receipt: expect error]
insert into items (receipt_id, name, amount_cents) values ('bbbbbbbb-0000-0000-0000-000000000001', 'X', 1);
\echo [10 B uses A person: expect error]
select save_receipt('{"id":"bbbbbbbb-0000-0000-0000-000000000009","store_name":"B","receipt_date":"2026-11-02","total_cents":10,"items":[{"id":"cccccccc-0000-0000-0000-000000000009","position":0,"name":"T","amount_cents":10,"category_id":"other","split_method":"equal","assignments":[{"person_id":"aaaaaaaa-0000-0000-0000-000000000001","position":0,"allocated_cents":10}]}]}');
\echo [11 B forges user_id: expect error]
insert into people (user_id, name) values ('11111111-1111-1111-1111-111111111111', 'Evil');
\echo [12 categories: 11]
select count(*) from categories;
\echo [13 signed out: expect error]
reset request.jwt.claim.sub;
select save_receipt('{"id":"bbbbbbbb-0000-0000-0000-000000000008","items":[]}');
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
\echo [14 A intact: KEELLS 2]
select store_name from receipts;
