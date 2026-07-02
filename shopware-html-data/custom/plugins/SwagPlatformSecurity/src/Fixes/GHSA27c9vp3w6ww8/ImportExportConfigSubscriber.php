<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA27c9vp3w6ww8;

use Shopware\Core\Content\ImportExport\Event\ImportExportBeforeExportRecordEvent;
use Shopware\Core\Content\ImportExport\Processing\Mapping\Mapping;
use Shopware\Core\Content\ImportExport\Struct\Config;
use Shopware\Core\Framework\DataAbstractionLayer\Dbal\EntityDefinitionQueryHelper;
use Shopware\Core\Framework\DataAbstractionLayer\DefinitionInstanceRegistry;
use Shopware\Core\Framework\DataAbstractionLayer\Field\Flag\ApiAware;
use Shopware\Core\Framework\Log\Package;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

#[Package('after-sales')]
readonly class ImportExportConfigSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private DefinitionInstanceRegistry $registry,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            ImportExportBeforeExportRecordEvent::class => 'onImportExportBeforeExportRecordEvent',
        ];
    }

    public function onImportExportBeforeExportRecordEvent(ImportExportBeforeExportRecordEvent $event): void
    {
        $config = $event->getConfig();

        $allowedMappings = $this->getAllowedMappings($config);

        $mappedKeys = array_map(
            static fn (Mapping $mapping): string => $mapping->getMappedKey(),
            $allowedMappings
        );

        $filteredRecord = array_intersect_key(
            $event->getRecord(),
            array_flip($mappedKeys)
        );

        $event->setRecord($filteredRecord);
    }

    /**
     * @return Mapping[]
     */
    private function getAllowedMappings(Config $config): array
    {
        $definition = $this->registry->getByEntityName(
            $config->get('sourceEntity')
        );

        return array_filter(
            $config->getMapping()->getElements(),
            static function (Mapping $mapping) use ($definition): bool {
                $fields = EntityDefinitionQueryHelper::getFieldsOfAccessor(
                    $definition,
                    $mapping->getKey()
                );

                foreach ($fields as $field) {
                    $flag = $field->getFlag(ApiAware::class);

                    if (!$flag instanceof ApiAware) {
                        return false;
                    }
                }

                return true;
            }
        );
    }
}
