-- MySQL dump 10.13  Distrib 5.5.52, for debian-linux-gnu (armv7l)
--
-- Host: localhost    Database: ascii
-- ------------------------------------------------------
-- Server version	5.5.52-0+deb8u1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `valid_option`
--

DROP TABLE IF EXISTS `valid_option`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `valid_option` (
  `vao_id` int(11) NOT NULL AUTO_INCREMENT,
  `vao_table` varchar(64) NOT NULL,
  `vao_code` int(11) NOT NULL,
  `vao_value` varchar(30) NOT NULL,
  PRIMARY KEY (`vao_id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `valid_option`
--

LOCK TABLES `valid_option` WRITE;
/*!40000 ALTER TABLE `valid_option` DISABLE KEYS */;
INSERT INTO `valid_option` VALUES (1,'site',1,'INSTANT_BANNED'),(2,'site',2,'BANNED'),(3,'site',3,'REGISTRATION'),(4,'site',4,'OPEN'),(5,'connect',1,'CONNECT'),(6,'connect',2,'DISCONNECT');
/*!40000 ALTER TABLE `valid_option` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `flag_definition`
--

DROP TABLE IF EXISTS `flag_definition`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `flag_definition` (
  `fde_flag_id` int(11) NOT NULL AUTO_INCREMENT,
  `fde_name` varchar(100) NOT NULL,
  `fde_letter` varchar(1) NOT NULL,
  `fde_created_by` varchar(75) DEFAULT NULL,
  `fde_created_date` datetime DEFAULT NULL,
  `fde_last_updated_by` varchar(75) DEFAULT NULL,
  `fde_last_updated_date` datetime DEFAULT NULL,
  `FDE_PERMISSION` int(11) NOT NULL DEFAULT '-1',
  PRIMARY KEY (`fde_flag_id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `flag_definition`
--

LOCK TABLES `flag_definition` WRITE;
/*!40000 ALTER TABLE `flag_definition` DISABLE KEYS */;
INSERT INTO `flag_definition` VALUES (-1,'ANYONE','A','Adrick','2016-09-30 12:09:52',NULL,NULL,-1),(0,'GOD','G','Adrick','2016-09-30 11:40:55',NULL,NULL,0),(1,'WIZARD','W','Adrick','2016-04-23 12:14:38',NULL,NULL,0),(2,'PLAYER','P','Adrick','2016-04-23 12:14:38',NULL,NULL,0),(3,'ROOM','R','Adrick','2016-04-23 12:14:38',NULL,NULL,0),(4,'EXIT','E','Adrick','2016-04-23 12:14:38',NULL,NULL,0),(5,'OBJECT','o','Adrick','2016-04-25 10:29:37',NULL,NULL,0),(6,'LISTENER','M','Adrick',NULL,NULL,NULL,-1),(7,'SOCKET','S','Adrick','2016-09-30 11:41:30',NULL,NULL,0);
/*!40000 ALTER TABLE `flag_definition` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2016-10-04  8:48:34
