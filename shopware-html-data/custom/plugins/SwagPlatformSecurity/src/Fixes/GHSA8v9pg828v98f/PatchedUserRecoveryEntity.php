<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA8v9pg828v98f;

use Shopware\Core\Framework\Log\Package;
use Shopware\Core\System\User\Aggregate\UserRecovery\UserRecoveryEntity;

#[Package('framework')]
class PatchedUserRecoveryEntity extends UserRecoveryEntity
{
    public function getHash(): string
    {
        $this->checkIfPropertyAccessIsAllowed('hash');

        return parent::getHash();
    }
}
