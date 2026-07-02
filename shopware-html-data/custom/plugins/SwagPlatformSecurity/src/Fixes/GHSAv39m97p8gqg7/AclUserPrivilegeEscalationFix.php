<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAv39m97p8gqg7;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('framework')]
class AclUserPrivilegeEscalationFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-v39m-97p8-gqg7';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.10.1';
    }
}
