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
-- Table structure for table `attribute`
--

DROP TABLE IF EXISTS `attribute`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `attribute` (
  `obj_id` int(11) NOT NULL,
  `atr_id` int(11) NOT NULL AUTO_INCREMENT,
  `atr_name` varchar(30) DEFAULT NULL,
  `atr_value` varchar(4096) DEFAULT NULL,
  `atr_created_by` varchar(30) DEFAULT NULL,
  `atr_created_date` date DEFAULT NULL,
  `atr_last_updated_by` varchar(30) DEFAULT NULL,
  `atr_last_updated_date` date DEFAULT NULL,
  PRIMARY KEY (`atr_id`),
  UNIQUE KEY `attribute_unq` (`obj_id`,`atr_name`),
  CONSTRAINT `attribute_ibfk_1` FOREIGN KEY (`obj_id`) REFERENCES `object` (`obj_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=39 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `connect`
--

DROP TABLE IF EXISTS `connect`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `connect` (
  `con_connect_id` int(11) NOT NULL AUTO_INCREMENT,
  `obj_id` int(11) NOT NULL,
  `con_hostname` varchar(255) NOT NULL,
  `con_timestamp` datetime NOT NULL,
  `con_type` int(11) NOT NULL,
  `con_socket` varchar(50) NOT NULL,
  `con_success` int(11) NOT NULL,
  PRIMARY KEY (`con_connect_id`),
  KEY `obj_id` (`obj_id`),
  CONSTRAINT `connect_ibfk_1` FOREIGN KEY (`obj_id`) REFERENCES `object` (`obj_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=641 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `content`
--

DROP TABLE IF EXISTS `content`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `content` (
  `obj_id` int(11) NOT NULL,
  `con_source_id` int(11) DEFAULT NULL,
  `con_dest_id` int(11) DEFAULT NULL,
  `con_type` int(11) NOT NULL,
  `con_created_by` varchar(100) NOT NULL,
  `con_created_date` datetime NOT NULL,
  `con_updated_by` varchar(100) DEFAULT NULL,
  `con_updated_date` datetime DEFAULT NULL,
  PRIMARY KEY (`obj_id`,`con_type`),
  KEY `obj_id` (`obj_id`),
  CONSTRAINT `content_ibfk_1` FOREIGN KEY (`obj_id`) REFERENCES `object` (`obj_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `flag`
--

DROP TABLE IF EXISTS `flag`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `flag` (
  `obj_id` int(11) NOT NULL,
  `ofg_id` int(11) NOT NULL AUTO_INCREMENT,
  `ofg_created_by` varchar(50) NOT NULL,
  `ofg_created_date` datetime NOT NULL,
  `fde_flag_id` int(11) NOT NULL,
  PRIMARY KEY (`ofg_id`),
  UNIQUE KEY `table_idx2` (`obj_id`,`fde_flag_id`),
  KEY `obj_id` (`obj_id`),
  KEY `fde_flag_id` (`fde_flag_id`),
  CONSTRAINT `flag_ibfk_1` FOREIGN KEY (`obj_id`) REFERENCES `object` (`obj_id`) ON DELETE CASCADE,
  CONSTRAINT `flag_ibfk_2` FOREIGN KEY (`fde_flag_id`) REFERENCES `flag_definition` (`fde_flag_id`)
) ENGINE=InnoDB AUTO_INCREMENT=106 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  PRIMARY KEY (`fde_flag_id`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `log`
--

DROP TABLE IF EXISTS `log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `log` (
  `log_id` int(11) NOT NULL AUTO_INCREMENT,
  `log_timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `log_message` varchar(4000) NOT NULL,
  `log_error` int(10) DEFAULT NULL,
  PRIMARY KEY (`log_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `object`
--

DROP TABLE IF EXISTS `object`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `object` (
  `obj_id` int(11) NOT NULL AUTO_INCREMENT,
  `obj_name` varchar(50) NOT NULL,
  `obj_password` varchar(41) DEFAULT NULL,
  `obj_owner` int(11) NOT NULL,
  `obj_created_by` varchar(50) NOT NULL,
  `obj_created_date` datetime NOT NULL,
  `obj_last_updated_by` varchar(50) DEFAULT NULL,
  `obj_last_updated_date` datetime DEFAULT NULL,
  `obj_home` int(11) NOT NULL,
  `obj_quota` int(11) DEFAULT NULL,
  PRIMARY KEY (`obj_id`)
) ENGINE=InnoDB AUTO_INCREMENT=113 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `site`
--

DROP TABLE IF EXISTS `site`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `site` (
  `ste_id` int(11) NOT NULL AUTO_INCREMENT,
  `ste_pattern` varchar(1024) NOT NULL,
  `ste_type` int(11) NOT NULL,
  `ste_end_date` datetime DEFAULT NULL,
  `ste_created_by` int(11) NOT NULL,
  `ste_created_date` datetime NOT NULL,
  `ste_last_updated_date` datetime DEFAULT NULL,
  `ste_last_updated_by` int(11) DEFAULT NULL,
  PRIMARY KEY (`ste_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2016-09-21 12:45:44
