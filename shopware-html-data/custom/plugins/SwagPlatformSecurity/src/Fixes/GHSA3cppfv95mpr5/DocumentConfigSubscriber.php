<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA3cppfv95mpr5;

use Shopware\Core\Checkout\Document\Event\CreditNoteOrdersEvent;
use Shopware\Core\Checkout\Document\Event\DeliveryNoteOrdersEvent;
use Shopware\Core\Checkout\Document\Event\DocumentOrderEvent;
use Shopware\Core\Checkout\Document\Event\InvoiceOrdersEvent;
use Shopware\Core\Checkout\Document\Event\StornoOrdersEvent;
use Shopware\Core\Checkout\Document\Zugferd\ZugferdInvoiceOrdersEvent;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Util\HtmlSanitizer;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

#[Package('after-sales')]
readonly class DocumentConfigSubscriber implements EventSubscriberInterface
{
    public function __construct(private HtmlSanitizer $htmlSanitizer)
    {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            StornoOrdersEvent::class => 'onDocumentEvent',
            InvoiceOrdersEvent::class => 'onDocumentEvent',
            CreditNoteOrdersEvent::class => 'onDocumentEvent',
            DeliveryNoteOrdersEvent::class => 'onDocumentEvent',
            ZugferdInvoiceOrdersEvent::class => 'onDocumentEvent',
        ];
    }

    public function onDocumentEvent(DocumentOrderEvent $event): void
    {
        $operations = $event->getOperations();

        foreach ($operations as $operation) {
            $config = $operation->getConfig();

            $config['documentComment'] = $this->htmlSanitizer->sanitize(
                $config['documentComment'] ?? '',
                [],
                true
            );

            $operation->assign([
                'config' => $config,
            ]);
        }
    }
}
