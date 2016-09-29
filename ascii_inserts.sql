--
-- initial inserts to get things started. Includes a initial password of
-- xyzzy for God.
--
LOCK TABLES `flag_definition` WRITE;
/*!40000 ALTER TABLE `flag_definition` DISABLE KEYS */;
INSERT INTO `flag_definition` VALUES
(1,'WIZARD','W','Adrick','2016-04-23 12:14:38',NULL,NULL),
(2,'PLAYER','P','Adrick','2016-04-23 12:14:38',NULL,NULL),
(3,'ROOM','R','Adrick','2016-04-23 12:14:38',NULL,NULL),
(4,'EXIT','E','Adrick','2016-04-23 12:14:38',NULL,NULL),
(5,'OBJECT','o','Adrick','2016-04-25 10:29:37',NULL,NULL),
(6,'LISTENER','M','Adrick',NULL,NULL,NULL);
/*!40000 ALTER TABLE `flag_definition` ENABLE KEYS */;
UNLOCK TABLES;


INSERT INTO object
( obj_id,
  obj_name,
  obj_password,
  obj_owner,
  obj_created_by,
  obj_created_date,
  obj_last_updated_by,
  obj_last_updated_date,
  obj_home,
  obj_quota
) values (
  0,
  'The Void',
  NULL,
  0,
  'God',
  now(),
  NULL,
  NULL,
  -1,
  NULL
);

INSERT INTO object
( obj_id,
  obj_name,
  obj_password,
  obj_owner,
  obj_created_by,
  obj_created_date,
  obj_last_updated_by,
  obj_last_updated_date,
  obj_home,
  obj_quota
) values (
  1,
  'God',
  '*151AF6B8C3A6AA09CFCCBD34601F2D309ED54888',
  0,
  'God',
  NOW(),
  NULL,
  NULL,
  0,
  0
);

LOCK TABLES `valid_option` WRITE;
/*!40000 ALTER TABLE `valid_option` DISABLE KEYS */;
INSERT INTO `valid_option` VALUES
(1,'site',1,'INSTANT_BANNED'),
(2,'site',2,'BANNED'),
(3,'site',3,'REGISTRATION'),
(4,'site',4,'OPEN'),
(5,'connect',1,'CONNECT'),
(6,'connect',2,'DISCONNECT');
/*!40000 ALTER TABLE `valid_option` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

