<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAgv8p48fr4fxg;

use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\Field\Flag\WriteProtected;
use Shopware\Core\Framework\DataAbstractionLayer\FieldCollection;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\System\Integration\IntegrationDefinition;

#[Package('fundamentals@framework')]
class PatchedIntegrationDefinition extends IntegrationDefinition
{
    protected function defineFields(): FieldCollection
    {
        $fields = parent::defineFields();
        $adminField = $fields->get('admin');

        if ($adminField !== null) {
            $writeProtected = $adminField->getFlag(WriteProtected::class);

            if (!$writeProtected instanceof WriteProtected || !$writeProtected->isAllowed(Context::SYSTEM_SCOPE)) {
                // @phpstan-ignore method.deprecated
                $adminField->addFlags(new WriteProtected(Context::SYSTEM_SCOPE));
            }
        }

        return $fields;
    }
}
