<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA9v82vcjxm76j;

use Swag\Security\Components\AbstractSecurityFix;

class EncodeActiveRouteParams extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-9v82-vcjxm-76j';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.2.1';
    }
}
