<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA8v9pg828v98f;

use Shopware\Core\Framework\DataAbstractionLayer\Field\CreatedAtField;
use Shopware\Core\Framework\DataAbstractionLayer\Field\Field;
use Shopware\Core\Framework\DataAbstractionLayer\Field\FkField;
use Shopware\Core\Framework\DataAbstractionLayer\Field\Flag\ApiAware;
use Shopware\Core\Framework\DataAbstractionLayer\Field\Flag\PrimaryKey;
use Shopware\Core\Framework\DataAbstractionLayer\Field\Flag\Required;
use Shopware\Core\Framework\DataAbstractionLayer\Field\IdField;
use Shopware\Core\Framework\DataAbstractionLayer\Field\OneToOneAssociationField;
use Shopware\Core\Framework\DataAbstractionLayer\Field\StringField;
use Shopware\Core\Framework\DataAbstractionLayer\FieldCollection;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\System\User\Aggregate\UserRecovery\UserRecoveryDefinition;
use Shopware\Core\System\User\UserDefinition;

#[Package('framework')]
class PatchedUserRecoveryDefinition extends UserRecoveryDefinition
{
    public function getEntityClass(): string
    {
        return PatchedUserRecoveryEntity::class;
    }

    protected function defineFields(): FieldCollection
    {
        return new FieldCollection([
            // @phpstan-ignore method.deprecated
            $this->addDescriptionIfSupported((new IdField('id', 'id'))->addFlags(new PrimaryKey(), new Required()), 'Unique identity of user recovery.'),
            // @phpstan-ignore method.deprecated, method.deprecated
            $this->addDescriptionIfSupported((new StringField('hash', 'hash'))->removeFlag(ApiAware::class)->addFlags(new Required()), 'Password hash for user recovery.'),
            // @phpstan-ignore method.deprecated
            $this->addDescriptionIfSupported((new FkField('user_id', 'userId', UserDefinition::class))->addFlags(new Required()), 'Unique identity of user.'),
            // @phpstan-ignore method.deprecated
            (new CreatedAtField())->addFlags(new Required()),

            new OneToOneAssociationField('user', 'user_id', 'id', UserDefinition::class, false),
        ]);
    }

    private function addDescriptionIfSupported(Field $field, string $description): Field
    {
        // @phpstan-ignore function.alreadyNarrowedType (keep runtime guard for cross-version compatibility)
        if (!method_exists($field, 'setDescription')) {
            return $field;
        }

        // @phpstan-ignore method.deprecated
        $field->setDescription($description);

        return $field;
    }
}
