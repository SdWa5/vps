<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAm8952hj38cg9;

use Swag\Security\Components\AbstractSecurityFix;

class MediaAggregations extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-m895-2hj3-8cg9';
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
