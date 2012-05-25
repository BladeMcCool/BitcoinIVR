-- MySQL dump 10.13  Distrib 5.1.62, for debian-linux-gnu (i486)
--
-- Host: localhost    Database: (whatever you like)
-- ------------------------------------------------------
-- Server version	5.1.62-0ubuntu0.10.04.1

--
-- Table structure for table `btcsys_user`
--

DROP TABLE IF EXISTS `btcsys_user`;
CREATE TABLE `btcsys_user` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `pin` int(10) unsigned NOT NULL DEFAULT '0',
  `btc_address` varchar(255) CHARACTER SET utf8 DEFAULT NULL,
  `receive_sms_from` varchar(255) CHARACTER SET utf8 DEFAULT NULL,
  `enabled` int(10) NOT NULL DEFAULT '0',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `modified` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created_admin_id` int(10) unsigned NOT NULL DEFAULT '0',
  `modified_admin_id` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=latin1;

--
-- Table structure for table `btcsys_addressbook`
--

DROP TABLE IF EXISTS `btcsys_addressbook`;
CREATE TABLE `btcsys_addressbook` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `syscode` int(10) unsigned DEFAULT NULL,
  `btc_address` varchar(255) CHARACTER SET utf8 DEFAULT NULL,
  `display_order` int(10) unsigned NOT NULL DEFAULT '0',
  `enabled` int(10) NOT NULL DEFAULT '0',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `modified` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created_admin_id` int(10) unsigned NOT NULL DEFAULT '0',
  `modified_admin_id` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `userid` (`userid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=latin1;

--
-- Table structure for table `btcsys_smsjunk`
--

DROP TABLE IF EXISTS `btcsys_smsjunk`;
CREATE TABLE `btcsys_smsjunk` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `btc_address` varchar(255) CHARACTER SET utf8 DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `modified` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created_admin_id` int(10) unsigned NOT NULL DEFAULT '0',
  `modified_admin_id` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `userid` (`userid`),
  KEY `btc_address` (`btc_address`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=latin1;

-- Dump completed on 2012-05-25 15:54:52
