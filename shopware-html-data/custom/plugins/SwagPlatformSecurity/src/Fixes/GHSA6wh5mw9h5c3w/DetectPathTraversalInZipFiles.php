<?php

declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA6wh5mw9h5c3w;

use Swag\Security\Components\AbstractSecurityFix;

class DetectPathTraversalInZipFiles extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-6wh5-mw9h-5c3w';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.3.1';
    }
}
